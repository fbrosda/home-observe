#!/usr/bin/guile \
-L ../ -e main -s
!#

(use-modules ((home-observe plenticore) #:prefix plenticore:))

(define* (read-config #:optional (path "/etc/home-observe.cfg"))
  (with-input-from-file path  read))

(define (main args)
  (let ((cfg (read-config)))
    (plenticore:observe (assoc-ref cfg "plenticore"))))
