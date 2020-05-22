#lang racket/base

;; ---------------------------------------------------------------------------------------------------

(require ffi/unsafe
         (prefix-in c: racket/contract)
         racket/format
         "base.rkt"
         "loadlib.rkt"
         "utils.rkt")

(provide build-translator make-out check-args
         (c:contract-out
          [make-giarg         (c:-> cpointer?)]
          [giargs             (c:->* ((c:listof translator?)) (list?) cpointer?)]
          [pointer-translator translator?]))

;; ---------------------------------------------------------------------------------------------------

(define tag-list '(void boolean int8 uint8 int16 uint16 int32 uint32 int64 uint64
                        float double gtype utf8 filename array interface glist gslist
                        ghash error unichar))

(define-gi* g-type-info-get-tag (_fun _pointer -> (_enum tag-list)))
(define-gi* g-type-info-is-pointer (_fun _pointer -> _bool))
(define-gi* g-type-info-get-param-type (_fun _pointer _int -> _info))
(define-gi* g-type-info-get-interface (_fun _pointer -> _info))
(define-gi* g-type-info-get-array-length (_fun _pointer -> _int))
(define-gi* g-type-info-get-array-fixed-size (_fun _pointer -> _int))
(define-gi* g-type-info-is-zero-terminated (_fun _pointer -> _bool))

(define-struct translator
  (>giarg >value check description)
  #:transparent)

(define _giarg (_union _bool _int8 _uint8 _int16 _uint16
                       _int32 _uint32 _int64 _uint64
                       _float _double _long _ulong _pointer _string))

(define (make-giarg) (malloc _giarg))

(define (pointer->giarg giarg value) 
  (ptr-set! giarg _pointer (if (procedure? value) (value ':this) value)))

(define (giarg->pointer giarg) 
  (ptr-ref giarg _pointer))

(define (describe-type type-info)
  (define tag (g-type-info-get-tag type-info))
  (~a (if (g-type-info-is-pointer type-info) "pointer to " "")
      tag
      (case tag
        ((interface)
         (~a " to " (g-type-info-get-interface type-info)))
        ((array)
         (~a " of " (describe-type (g-type-info-get-param-type type-info 0))
             ", length param: " (g-type-info-get-array-length type-info)
             ", fixed length: " (g-type-info-get-array-fixed-size type-info)            
             (if (g-type-info-is-zero-terminated type-info) ", zero terminated" "")))
        ((ghash)
         (~a " of {" (describe-type (g-type-info-get-param-type type-info 0))
             ", " (describe-type (g-type-info-get-param-type type-info 1))
             "}"))
        (else ""))))

(define pointer-translator
  (make-translator
   pointer->giarg
   giarg->pointer 
   cpointer?
   "instance pointer"))

(define (build-translator type)
  (printf "build-translator ~a~n" type)
  (printf "~a~n" (describe-type type))
  (define tag (g-type-info-get-tag type))
  (define pos (- (find-pos tag tag-list) 1))
  (define pointer? (g-type-info-is-pointer type))
  (printf "tag: ~a, pos: ~a, pointer: ~a~n" tag pos pointer?)
  (define value->giarg
    (if pointer?
        (case tag
          [(utf8 filename)
           (printf "its utf8 or filename~n")
           (λ (giarg value)
             (ptr-set! giarg _string value))] 
          [else
           (printf "pointer something else~n")
           pointer->giarg])
        (case tag
          [(void)
           (printf "non-pointer void~n")
           (λ (giarg value) (ptr-set! giarg _pointer #f))]
          [(boolean int8 uint8 int16 uint16 
                    int32 uint32 int64 uint64 float double)
           (printf "non-pointer primitive number~n")
           (λ (giarg value)
             (union-set! (ptr-ref giarg _giarg) pos value))]
          [(gtype interface)
           (printf "non-pointer gtype or interface~n")
           (λ (giarg value)
             (ptr-set! giarg _ulong value))]
          [else
           (printf "non-pointer something else~n")
           pointer->giarg])))
  (define giarg->value
    (if pointer?
        (case tag
          [(utf8 filename) (λ (giarg)
                             (ptr-ref giarg _string))]
          [else giarg->pointer])
        (case tag
          [(void) (λ (giarg) #f)]
          [(boolean int8 uint8 int16 uint16 
                    int32 uint32 int64 uint64 float double) (λ (giarg)
                                                              (union-ref 
                                                               (ptr-ref giarg _giarg) 
                                                               pos))]
          [(gtype interface) (λ (giarg)
                     (ptr-ref giarg _ulong))]
          [else giarg->pointer])))
  (define check-value
    (if pointer? 
        (case tag
          [(utf8 filename) string?]
          [else (λ (x) (or (cpointer? x) (and (procedure? x) (cpointer? (x ':this)))))])
        (case tag
          [(void)
           (λ (value) #t)]
          [(boolean) boolean?]
          [(gtype interface int8 uint8 int16 uint16 
                  int32 uint32 int64 uint64) exact-integer?]
          [(float double) flonum?]
          [else cpointer?])))
  (define description (describe-type type))
  (make-translator value->giarg giarg->value check-value description))

(define (giargs translators [vs '()])
  (define ptr (malloc _giarg (length translators)))
  (for ([translator (in-list translators)]
        [value (in-list vs)]
        [i (in-naturals)])
    ((translator->giarg translator) (ptr-add ptr i _giarg) value))
  ptr)

(define (make-out res-trans giarg-res [out-translators null] [giargs-out #f])
  (printf "make-out ~a ~a ~a ~a~n"
          res-trans giarg-res out-translators giargs-out)
  (apply values
         (cons
          ((translator->value res-trans) giarg-res)
          (for/list ([translator (in-list out-translators)]
                     [i (in-naturals)])
            ((translator->value translator) (ptr-add giargs-out i _giarg))))))

(define (check-args args translators name)
  (unless (= (length args) (length translators))
    (apply raise-arity-error (string->symbol name) (length translators) args))
  (for ([arg (in-list args)]
        [translator (in-list translators)])
    (unless ((translator-check translator) arg)
      (raise-argument-error (string->symbol name) (translator-description translator) arg))))
