#lang racket/base
;; ---------------------------------------------------------------------------------------------------

(require ffi/unsafe
         ffi/unsafe/alloc
         racket/match
         "base.rkt"
         "contract.rkt"
         (prefix-in f: "field.rkt")
         "function.rkt"
         "gtype.rkt"
         "loadlib.rkt")

(provide build-object-ptr _gobject gtype->ffi set!-set-properties! set!-get-properties
 (contract-out
  [build-object ffi-builder?]))

;; ---------------------------------------------------------------------------------------------------

(define-gi* g-object-info-find-method (_fun _pointer _string -> _info))
(define-gi* g-object-info-get-parent (_fun _pointer -> _info))
(define-gi* g-object-info-get-n-fields (_fun _pointer -> _int))
(define-gi* g-object-info-get-field (_fun _pointer _int -> _info))

(define (find-method info name)
  (and info
       (or (g-object-info-find-method info name)
           (find-method (g-object-info-get-parent info) name))))

(define-gobject* g-object-unref (_fun _pointer -> _void) #:wrap (deallocator))
(define-gobject* g-object-ref-sink (_fun _pointer -> _pointer) #:wrap (allocator g-object-unref))

;;; will be defined in property.rkt
(define set-properties! #f)
(define (set!-set-properties! arg) (set! set-properties! arg))
(define get-properties #f)
(define (set!-get-properties arg) (set! get-properties arg))

(define (closures info)
  (define (call name args)
    (printf "calling method of object name: ~a, args: ~a~n" name args)
    (define function-info (find-method info (c-name name)))
    (if function-info
        (let ([f (build-function function-info)])
          (printf "applying functions to: ~a~n" args)
          (apply f args))
        (raise-argument-error 'build-object "FFI method name" name)))
  (define fields-dict
    (for/list ([i (in-range (g-object-info-get-n-fields info))])
      (define field-info (g-object-info-get-field info i))
      (cons (g-base-info-get-name field-info) field-info)))
  (define (find-field name)
    (cdr (or (assoc (c-name name) fields-dict)
             (raise-argument-error 'build-object "FFI field name" name))))
  (define (closure this)
    (define signals (box null))
    (λ (name . args)
      (case name
        [(:this) this]
        [(:signals) signals]
        [(:field)
         (match args
           [(list name) (f:get this (find-field name))])]
        [(:set-field!) 
         (match args
           [(list name value) (f:set this (find-field name) value)])]
        [(:set-properties!)
         (set-properties! this args)]
        [(:properties)
         (get-properties this args)]
        [else (call name (cons this args))])))
  (values call closure))

(define (build-object info)
  (printf "build-object ~a~n" info)
  (define-values (call closure) (closures info))
  (λ (name . args)
    (printf "build-object closure with name ~a, args ~a~n" name args)
    (define v (call name args))
    (printf "v is ~a~n" v)
    ;; we sink the object and create a closure
    ;; over if it the return type is an object
    (if (cpointer? v)
        (closure (g-object-ref-sink v))
        v)))

(define (build-object-ptr info ptr)
  (define-values (call closure) (closures info))
  (closure ptr))

(define-gi* g-irepository-find-by-gtype (_fun (_pointer = #f) _long -> _pointer))

(define (gobject gtype ptr)
  (let ([info (g-irepository-find-by-gtype gtype)])
      (if (and info (eq? (g-base-info-get-type info) 'object))
          (build-object-ptr info ptr)
          (raise-argument-error 'gi-ffi "gtype not found in GI" gtype))))

(define _gobject (make-ctype _pointer (λ (x) (x ':this)) (λ (x) (gobject (gtype x) x))))

(define (gtype->ffi gtype)
  (case-gtype gtype
    [(invalid  void) _void]
    [(char)    _byte]
    [(uchar)   _ubyte]
    [(boolean) _bool]
    [(int)     _int]
    [(uint)    _uint]
    [(long)    _long]
    [(ulong)   _ulong]
    [(int64)   _int64]
    [(uint64)  _uint64]
    [(float)   _float]
    [(double)  _double]
    [(pointer) _pointer]
    [(string)  _string]
    [else      _gobject]))

