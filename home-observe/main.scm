#!/usr/bin/guile \
-L ../ -e main -s
!#

(use-modules (home-observe scram-auth)
             (web client)
             (web uri)
             (json))

(define (main args)
  (with-rfc5802-auth "***"
                     (lambda (token)
                       (call-with-values (lambda ()
                                           (http-post (build-uri 'http #:host "plenticore.fritz.box" #:path "/api/v2/events/latest")
                                                      #:headers `((content-type application/json (charset . "utf-8"))
                                                                  (accept (application/json))
                                                                  (accept-encoding (1000 . "gzip") (1000 . "deflate"))
                                                                  (authorization . (bearer ,token)))
                                                      #:body (scm->json-string `(("language" . "de-de")))))
                         (lambda (res body)
                           (format #t "~s~%" res)
                           (format #t "~s~%" (json-string->scm (ensure-string body)))))))
  (newline))
