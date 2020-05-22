#lang racket/base
;; ---------------------------------------------------------------------------------------------------

(require ffi/unsafe
         ffi/unsafe/alloc
         racket/function
         "loadlib.rkt")

(provide _info g-base-info-get-name g-base-info-get-type)

;; ---------------------------------------------------------------------------------------------------

(define-gi* g-base-info-unref (_fun _pointer -> _void)
  #:wrap (deallocator))

(define-gi* g-base-info-get-name (_fun _pointer -> _string))

;; Available types are described here:
;; https://developer.gnome.org/gi/stable/GIBaseInfo.html#GIInfoType
(define-gi* g-base-info-get-type
  (_fun _pointer -> 
        (_enum '(invalid
                 function
                 callback
                 struct
                 boxed 
                 enum
                 flags
                 object
                 interface
                 constant
                 invalid
                 union
                 value
                 signal
                 vfunc
                 property
                 field
                 arg
                 type
                 unresolved))))

(define _info (make-ctype _pointer #f ((allocator g-base-info-unref) identity)))
