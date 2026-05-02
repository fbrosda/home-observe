#!/usr/bin/guile \
-L ../ -e main -s
!#

(use-modules (ice-9 threads)
             (ice-9 format)
             (srfi srfi-34)
             ((home-observe plenticore) #:prefix plenticore:)
             ((home-observe idm) #:prefix idm:))

(define (log fmt . args)
  (apply format #t fmt args)
  (newline))

(define* (read-config #:optional (path "/etc/home-observe.cfg"))
  (guard (e ((system-error? e)
             (error "failed to open config ~a: ~a" path (system-error-strerror e)))
            (else
             (error "failed to read config ~a: ~s" path e)))
    (with-input-from-file path read)))

(define (run-observer name fn cfg)
  (let loop ()
    (catch #t
      (lambda ()
        (fn cfg))
      (lambda (key . args)
        (log "~a observer crashed: ~s ~s" name key args)
        (log "~a reconnecting in 5s..." name)
        (sleep 5)
        (loop)))))

(define (main args)
  (log "home-observe starting")
  (let ((cfg (read-config)))
    (log "config loaded")
    (let* ((plenticore-thread
            (call-with-new-thread
             (lambda ()
               (run-observer "plenticore" plenticore:observe
                             (assoc-ref cfg "plenticore")))))
           (idm-thread
            (call-with-new-thread
             (lambda ()
               (run-observer "idm" idm:observe
                             (assoc-ref cfg "idm"))))))
       (catch #t
         (lambda ()
           (join-thread plenticore-thread)
           (join-thread idm-thread))
         (lambda (key . args)
           (log "thread join error: ~s ~s" key args))))))
