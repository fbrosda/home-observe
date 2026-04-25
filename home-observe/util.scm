(define-module (home-observe util)
  #:use-module (dbi dbi)
  #:export (with-dbi-handle))

(define (with-dbi-handle cfg thunk)
  (let ((handle #f))
    (dynamic-wind
      (lambda ()
        (set! handle (dbi-open "postgresql" (assoc-ref cfg "connection"))))
      (lambda ()
        (thunk handle))
      (lambda ()
        (dbi-close handle)))))
