(define-module (home-observe aes)
  #:use-module (rnrs bytevectors)
  #:use-module (system foreign)
  #:export (aes-gcm-encrypt))

(define libgcrypt (dynamic-link "libgcrypt"))

(define GCRY_CIPHER_AES256 9)
(define GCRY_CIPHER_MODE_GCM 9)

(define (check err msg)
  (unless (= err 0)
    (error msg (pointer->string (gcry_strerror err)))))

(define gcry_cipher_open
  (pointer->procedure int
    (dynamic-func "gcry_cipher_open" libgcrypt)
    (list '* int int int)))

(define gcry_cipher_close
  (pointer->procedure void
    (dynamic-func "gcry_cipher_close" libgcrypt)
    (list '*)))

(define gcry_cipher_setkey
  (pointer->procedure int
    (dynamic-func "gcry_cipher_setkey" libgcrypt)
    (list '* '* size_t)))

(define gcry_cipher_setiv
  (pointer->procedure int
    (dynamic-func "gcry_cipher_setiv" libgcrypt)
    (list '* '* size_t)))

(define gcry_cipher_encrypt
  (pointer->procedure int
    (dynamic-func "gcry_cipher_encrypt" libgcrypt)
    (list '* '* size_t '* size_t)))

(define gcry_cipher_gettag
  (pointer->procedure int
    (dynamic-func "gcry_cipher_gettag" libgcrypt)
    (list '* '* size_t)))

(define gcry_strerror
  (pointer->procedure '* (dynamic-func "gcry_strerror" libgcrypt)
                      (list int)))

(define (aes-gcm-encrypt key nonce plaintext)
  (let* ((ctx-ptr (make-bytevector (sizeof '*)))
         (ctx (bytevector->pointer ctx-ptr))
         (opened? #f))
    (dynamic-wind
      (lambda ()
        (gcry_cipher_open ctx GCRY_CIPHER_AES256 GCRY_CIPHER_MODE_GCM 0)
        (set! opened? #t)
        (set! ctx (dereference-pointer ctx))
        (check (gcry_cipher_setkey ctx
                                   (bytevector->pointer key)
                                   (bytevector-length key))
               "setkey error: ")
        (check (gcry_cipher_setiv ctx
                                  (bytevector->pointer nonce)
                                  (bytevector-length nonce))
               "setiv error: "))
      (lambda ()
        (let* ((len (bytevector-length plaintext))
               (ciphertext (make-bytevector len))
               (tag (make-bytevector 16)))
          (check (gcry_cipher_encrypt ctx
                                      (bytevector->pointer ciphertext)
                                      len
                                      (bytevector->pointer plaintext)
                                      len)
                 "encrypt error: ")
          (gcry_cipher_gettag ctx (bytevector->pointer tag) 16)
          (values ciphertext tag)))
      (lambda ()
        (when opened?
          (gcry_cipher_close ctx))))))
