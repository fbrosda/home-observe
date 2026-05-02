(define-module (home-observe plenticore)
  #:use-module (dbi dbi)
  #:use-module (gcrypt base64)
  #:use-module (gcrypt hash)
  #:use-module (gcrypt mac)
  #:use-module (gcrypt random)
  #:use-module (home-observe aes)
  #:use-module (home-observe util)
  #:use-module (ice-9 match)
  #:use-module (json)
  #:use-module (rnrs bytevectors)
  #:use-module ((scheme base) #:select (bytevector-append))
  #:use-module (srfi srfi-34)
  #:use-module (web client)
  #:use-module (web response)
  #:use-module (web uri)
  #:export (observe))

(define *host* "plenticore.fritz.box")
(define *login-start* "/api/v2/auth/start")
(define *login-finish* "/api/v2/auth/finish")
(define *create-session* "/api/v2/auth/create_session")
(define *refresh-session* "/api/v2/auth/refresh")
(define *processdata* "/api/v2/processdata")

(define *api-headers* '((content-type application/json (charset . "utf-8"))
                        (accept (application/json))
                        (accept-encoding (1000 . "gzip") (1000 . "deflate"))))

(define (api-post host path body . maybe-headers)
  (let ((headers (append (if (null? maybe-headers) '() (car maybe-headers))
                         *api-headers*)))
    (call-with-values
        (lambda ()
          (http-post (build-uri 'http #:host host #:path path)
                     #:headers headers
                     #:body body))
      (lambda (res body)
        (json-string->scm (ensure-string body))))))

(define (scram-nonce n)
  (u8-list->bytevector (map (lambda (_) (random 256)) (iota n))))

(define (ensure-string o)
  (if (bytevector? o)
    (utf8->string o)
    o))

(define (bytevector-xor a b)
  (u8-list->bytevector (map logxor (bytevector->u8-list a) (bytevector->u8-list b))))

(define (pbkdf2 pwd salt rounds)
  (let loop ((i rounds)
             (up (bytevector-append salt (u8-list->bytevector '(0 0 0 1))))
             (res #f))
    (if (= i 0)
      res
      (let ((ui (sign-data pwd up #:algorithm (mac-algorithm hmac-sha256))))
        (loop (1- i) ui (if res
                          (bytevector-xor res ui)
                          ui))))))

(define (auth-start host client-nonce)
  (api-post host *login-start*
            (scm->json-string `(("username" . "user")
                                ("nonce" . ,client-nonce)))))

(define (auth-finish host client-proof transaction-id)
  (api-post host *login-finish*
            (scm->json-string `(("proof" . ,(base64-encode client-proof))
                                ("transactionId" . ,(base64-encode transaction-id))))))

(define (create-session host session-nonce transaction-id cipher-text auth-tag)
  (api-post host *create-session*
            (scm->json-string `(("iv" . ,(base64-encode session-nonce))
                                ("tag" . ,(base64-encode auth-tag))
                                ("transactionId" . ,(base64-encode transaction-id))
                                ("payload" . ,(base64-encode cipher-text))))))

(define (refresh-session host refresh-token)
  (api-post host *refresh-session*
            (scm->json-string `(("refresh_token" . ,refresh-token)))))

(define (with-rfc5802-auth host pwd thunk)
  (let ((token #f)
        (refresh-token #f))
    (let auth-loop ((delay 5))
      (dynamic-wind
        (lambda ()
          (let* ((client-nonce (base64-encode (scram-nonce 16)))
                 (srv-start (auth-start host client-nonce))
                 (rounds (assoc-ref srv-start "rounds"))
                 (salt (base64-decode (assoc-ref srv-start "salt")))
                 (server-nonce (base64-decode (assoc-ref srv-start "nonce")))
                 (transaction-id (base64-decode (assoc-ref srv-start "transactionId")))
                 (salted-pwd (pbkdf2 pwd salt rounds))
                 (client-key (sign-data salted-pwd "Client Key" #:algorithm (mac-algorithm hmac-sha256)))
                 (stored-key (sha256 client-key))
                 (auth-msg (format #f "n=user,r=~a,r=~a,s=~a,i=~a,c=biws,r=~a"
                                   client-nonce
                                   (base64-encode server-nonce)
                                   (base64-encode salt)
                                   rounds
                                   (base64-encode server-nonce)))
                 (client-signature (sign-data stored-key auth-msg #:algorithm (mac-algorithm hmac-sha256)))
                 (client-proof (bytevector-xor client-key client-signature))
                 (server-key (sign-data salted-pwd "Server Key" #:algorithm (mac-algorithm hmac-sha256)))
                 (server-signature (sign-data server-key auth-msg #:algorithm (mac-algorithm hmac-sha256)))

                 (srv-finish (auth-finish host client-proof transaction-id))
                 (session-token (string->utf8 (assoc-ref srv-finish "token")))
                 (signature (base64-decode (assoc-ref srv-finish "signature")))
                 (session-key (if (equal? signature server-signature)
                                (sign-data stored-key (bytevector-append (string->utf8 "Session Key") (string->utf8 auth-msg) client-key) #:algorithm (mac-algorithm hmac-sha256))
                                (error "Server signature missmatch!")))
                 (session-nonce (scram-nonce 16)))

            (call-with-values (lambda ()
                                (aes-gcm-encrypt session-key session-nonce session-token))
              (lambda (cipher-text auth-tag)
                (let* ((session (create-session host session-nonce transaction-id cipher-text auth-tag))
                       (refreshToken (assoc-ref session "refreshToken"))
                       (authToken (assoc-ref session "token")))
                  (set! token (string->symbol authToken))
                  (set! refresh-token refreshToken))))))
        (lambda ()
          (let retry ()
            (guard (e (else
                       (log-error e)
                       (let* ((session (refresh-session host refresh-token))
                              (new-token (assoc-ref session "token"))
                              (new-refresh (assoc-ref session "refreshToken")))
                         (if (and new-token new-refresh)
                           (begin
                             (set! token (string->symbol new-token))
                             (set! refresh-token new-refresh))
                           (error "refresh returned error response: ~s" session)))
                       (retry)))
              (thunk token))))
        (lambda () (sleep delay)))
      (auth-loop (min (* delay 2) 120)))))

(define (get-field data module field)
  (let ((module-value (assoc-ref (car (filter (lambda (elem) (string=? module (assoc-ref elem "moduleid"))) (vector->list data)))
                                 "processdata")))
    (assoc-ref (car (filter (lambda (elem) (string=? field (assoc-ref elem "id"))) (vector->list module-value)))
               "value")))

(define (storedata handle data)
  ;; (format #t "~s~%" data)
  (let* ((home-p (get-field data "devices:local" "Home_P"))
         (home-p-pv (get-field data "devices:local" "HomePv_P"))
         (home-p-bat (get-field data "devices:local" "HomeBat_P"))
         (home-p-grid (get-field data "devices:local" "HomeGrid_P"))

         (iv-state (get-field data "devices:local" "Inverter:State"))
         (iv-limit (get-field data "devices:local" "LimitEvuAbs"))
         (iv-em-state (get-field data "devices:local" "EM_State"))
         (iv-digi-in (get-field data "devices:local" "DigitalIn"))
         (iv-p (get-field data "devices:local:ac" "P"))
         (iv-freq (get-field data "devices:local:ac" "Frequency"))
         (iv-cosphi (get-field data "devices:local:ac" "CosPhi"))

         (iv-l1-u (get-field data "devices:local:ac" "L1_U"))
         (iv-l1-i (get-field data "devices:local:ac" "L1_I"))
         (iv-l1-p (get-field data "devices:local:ac" "L1_P"))
         (iv-l2-u (get-field data "devices:local:ac" "L2_U"))
         (iv-l2-i (get-field data "devices:local:ac" "L2_I"))
         (iv-l2-p (get-field data "devices:local:ac" "L2_P"))
         (iv-l3-u (get-field data "devices:local:ac" "L3_U"))
         (iv-l3-i (get-field data "devices:local:ac" "L3_I"))
         (iv-l3-p (get-field data "devices:local:ac" "L3_P"))

         (pv1-u (get-field data "devices:local:pv1" "U"))
         (pv1-i (get-field data "devices:local:pv1" "I"))
         (pv1-p (get-field data "devices:local:pv1" "P"))
         (pv2-u (get-field data "devices:local:pv2" "U"))
         (pv2-i (get-field data "devices:local:pv2" "I"))
         (pv2-p (get-field data "devices:local:pv2" "P"))

         (bat-u (get-field data "devices:local:battery" "U"))
         (bat-i (get-field data "devices:local:battery" "I"))
         (bat-p (get-field data "devices:local:battery" "P"))
         (bat-soc (get-field data "devices:local:battery" "SoC"))
         (bat-cycles (get-field data "devices:local:battery" "Cycles"))

         (grid-p (- iv-p home-p)))
    (dbi-query handle (format #f "insert into plenticore (time,
home_p, home_p_pv, home_p_bat, home_p_grid,
iv_state, iv_limit, iv_em_state, iv_digi_in, iv_p, iv_freq, iv_cosphi,
iv_l1_u, iv_l1_i, iv_l1_p, iv_l2_u, iv_l2_i, iv_l2_p, iv_l3_u, iv_l3_i, iv_l3_p,
pv1_u, pv1_i, pv1_p, pv2_u, pv2_i, pv2_p,
bat_u, bat_i, bat_p, bat_soc, bat_cycles,
grid_p
) values (now(),
~s, ~s, ~s, ~s,
~s, ~s, ~s, ~s::bit(4), ~s, ~s, ~s,
~s, ~s, ~s, ~s, ~s, ~s, ~s, ~s, ~s,
~s, ~s, ~s, ~s, ~s, ~s,
~s, ~s, ~s, ~s, ~s,
~s
)"
                              home-p home-p-pv home-p-bat home-p-grid
                              iv-state iv-limit iv-em-state iv-digi-in iv-p iv-freq iv-cosphi
                              iv-l1-u iv-l1-i iv-l1-p iv-l2-u iv-l2-i iv-l2-p iv-l3-u iv-l3-i iv-l3-p
                              pv1-u pv1-i pv1-p pv2-u pv2-i pv2-p
                              bat-u bat-i bat-p bat-soc bat-cycles
                              grid-p))))

(define *process-args* #((("moduleid" . "devices:local")
                          ("processdataids" . #("Home_P" "HomePv_P" "HomeBat_P" "HomeGrid_P" "EM_State" "DigitalIn" "LimitEvuAbs" "Inverter:State")))
                         (("moduleid" . "devices:local:pv1")
                          ("processdataids" . #("P" "I" "U")))
                         (("moduleid" . "devices:local:pv2")
                          ("processdataids" . #("P" "I" "U")))
                         (("moduleid" . "devices:local:ac")
                          ("processdataids" . #("P" "Frequency" "CosPhi" "L1_U" "L1_I" "L1_P" "L2_U" "L2_I" "L2_P" "L3_U" "L3_I" "L3_P")))
                         (("moduleid" . "devices:local:battery")
                          ("processdataids" . #("P" "I" "U" "SoC" "Cycles")))))

(define (processdata host token handle)
  (let ((data (api-post host *processdata*
                        (scm->json-string *process-args*)
                        `((authorization . (bearer ,token))))))
    (storedata handle data)))

(define (init handle)
  (dbi-query handle "CREATE TABLE IF NOT EXISTS plenticore (
  time        TIMESTAMPTZ NOT NULL,

  home_p double precision not null,
  home_p_pv double precision not null,
  home_p_bat double precision not null,
  home_p_grid double precision not null,

  iv_state smallint not null,
  iv_limit double precision not null,
  iv_em_state smallint not null,
  iv_digi_in bit(4) not null,
  iv_p double precision not null,
  iv_freq double precision not null,
  iv_cosphi double precision not null,
  iv_l1_u double precision not null,
  iv_l1_i double precision not null,
  iv_l1_p double precision not null,
  iv_l2_u double precision not null,
  iv_l2_i double precision not null,
  iv_l2_p double precision not null,
  iv_l3_u double precision not null,
  iv_l3_i double precision not null,
  iv_l3_p double precision not null,

  pv1_u double precision not null,
  pv1_i double precision not null,
  pv1_p double precision not null,

  pv2_u double precision not null,
  pv2_i double precision not null,
  pv2_p double precision not null,

  bat_u double precision not null,
  bat_i double precision not null,
  bat_p double precision not null,
  bat_soc smallint not null,
  bat_cycles integer not null,

  grid_p double precision not null ) WITH (timescaledb.hypertable);"))

(define (observe cfg)
  (let ((host (or (assoc-ref cfg "host") *host*)))
    (with-rfc5802-auth host (assoc-ref cfg "password")
                       (lambda (token)
                         (with-dbi-handle cfg (lambda (handle)
                                                (init handle)
                                                (let loop ()
                                                  (processdata host token handle)
                                                  (sleep 10)
                                                  (loop))))))))
