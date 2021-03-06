#lang racket/base
(require (except-in racket/contract ->))
(provide (contract-out 
          [gi-ffi (->* (string?) (string?) procedure?)]
          [connect (->* (procedure? string? procedure?) (list?) exact-integer?)]))
         ;get-properties set-properties!
         ;pointer field set-field!)

(require "signal.rkt" "loadlib.rkt" "glib.rkt" ffi/unsafe 
         "base.rkt" "function.rkt" "object.rkt" "struct.rkt" "enum.rkt" "const.rkt" "property.rkt")


(define-gi* g-irepository-require (_fun (_pointer = #f) _string _string _int _pointer -> _pointer))

(define (require-repository namespace #:version [version #f] #:lazy [lazy #f])
  (with-g-error (g-error)
    (or (g-irepository-require namespace version (if lazy 1 0) g-error)
        (raise-g-error g-error))))
        
;(define-gi* g-irepository-get-info (_fun (_pointer = #f) _string _int -> _pointer))
;(define-gi* g-irepository-get-n-infos (_fun (_pointer = #f) _string -> _int))

(define-gi* g-irepository-find-by-name (_fun (_pointer = #f) _string _string -> _info))

(define (build-interface info args)
  (case (g-base-info-get-type info)
    [(function) (apply (build-function info) args)]
    [(object) (apply (build-object info) args)]
    [(struct) (apply (build-struct info) args)]
    [(enum) (apply (build-enum info) args)]
    [(constant) (get-const info)]))
  

(define (gi-ffi namespace [version #f])
  (require-repository namespace #:version version)
  (λ (name . rest)
    (let ([info (g-irepository-find-by-name namespace (c-name name))])
      (if info
          (build-interface info rest)
          (raise-argument-error 'gi-ffi "name of FFI bind" name)))))