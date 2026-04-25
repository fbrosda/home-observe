#!/usr/bin/guile \
-L ../ -e main -s
!#

(use-modules (ice-9 threads)
             ((home-observe plenticore) #:prefix plenticore:)
             ((home-observe idm) #:prefix idm:))

(define* (read-config #:optional (path "/etc/home-observe.cfg"))
  (with-input-from-file path  read))

(define (main args)
  (let* ((cfg (read-config))
         (plenticore-thread (call-with-new-thread (lambda ()
                                                    (plenticore:observe (assoc-ref cfg "plenticore")))))
         (idm-thread (call-with-new-thread (lambda ()
                                             (idm:observe (assoc-ref cfg "idm"))))))
    (join-thread plenticore-thread)
    (join-thread idm-thread)))
