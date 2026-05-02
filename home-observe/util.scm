(define-module (home-observe util)
  #:use-module (dbi dbi)
  #:use-module (ice-9 exceptions)
  #:export (with-dbi-handle
            log-error))

(define (log-error e)
  (let ((msg (catch #t
               (lambda () (exception-message e))
               (lambda _ #f))))
    (format #t "error: ~a\n" (or msg e))))

(define (with-dbi-handle cfg thunk)
  (let ((handle #f))
    (dynamic-wind
      (lambda ()
        (set! handle (dbi-open "postgresql" (assoc-ref cfg "connection"))))
      (lambda ()
        (thunk handle))
      (lambda ()
        (when handle
          (dbi-close handle)
          (set! handle #f))))))
