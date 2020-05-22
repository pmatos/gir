#lang racket/base
;; ---------------------------------------------------------------------------------------------------

(require ffi/unsafe
         (except-in racket/contract
                    ->)
         "base.rkt"
         "const.rkt"
         "enum.rkt"
         "function.rkt"
         "glib.rkt"
         "gtype.rkt"
         "loadlib.rkt"
         "object.rkt"
         "signal.rkt"
         "struct.rkt")

(provide
 (contract-out 
  [gi-ffi (->* (string?) (string?) procedure?)]
  [connect (->* (procedure? string? procedure?) (list?) exact-integer?)]))

;; ---------------------------------------------------------------------------------------------------

(define-gi* g-irepository-require (_fun (_pointer = #f) _string _string _int _pointer -> _pointer))

(define (require-repository namespace #:version [version #f] #:lazy [lazy #f])
  (with-g-error (g-error)
    (or (g-irepository-require namespace version (if lazy 1 0) g-error)
        (raise-g-error g-error))))

(define-gi* g-irepository-find-by-name (_fun (_pointer = #f) _string _string -> _info))
(define-gi* g-info-type-to-string (_fun _info -> _string))

(define (build-interface info args)
  (printf "build-interface ~a ~a~n" info args)
  (case (g-base-info-get-type info)
    [(function)
     (printf "function~n")
     (define f (build-function info))
     (printf "applying functions to: ~a~n" args)
     (apply f args)]
    [(object)
     (printf "object~n")
     (apply (build-object info) args)]
    [(struct)
     (printf "struct~n")
     (apply (build-struct info) args)]
    [(enum)
     (printf "enum~n")
     (apply (build-enum info) args)]
    [(constant)
     (printf "constant~n")
     (get-const info)]))
  

(define (gi-ffi namespace [version #f])
  (require-repository namespace #:version version)
  (λ (name . rest)
    (printf "gi-ffi closure name ~a, rest ~a~n" name rest)
    (let ([info (g-irepository-find-by-name namespace (c-name name))])
      (if info
          (build-interface info rest)
          (raise-argument-error 'gi-ffi "name of FFI bind" name)))))
