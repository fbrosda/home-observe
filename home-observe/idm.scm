(define-module (home-observe idm)
  #:use-module (dbi dbi)
  #:use-module (home-observe util)
  #:use-module (ice-9 iconv)
  #:use-module (json)
  #:use-module (srfi srfi-34)
  #:use-module (web socket client)
  #:export (observe))

(define (uri-for host password)
  (format #f "ws://~a:61220/?auth_code=~a" host password))

(define (log-info fmt . args)
  (apply format #t fmt args)
  (newline))

(define (with-websocket uri thunk)
  (let ((ws #f))
    (dynamic-wind
      (lambda ()
        (set! ws (open-websocket-for-uri uri))
        (let ((greeting (websocket-receive ws)))
          (log-info "idm websocket connected: ~a" greeting)))
      (lambda ()
        (thunk ws))
      (lambda ()
        (when ws (close-websocket ws))))))

(define (safe-ref data key)
  (and data (assoc-ref data key)))

(define (safe-string->number v)
  (and v (string? v) (string->number v)))

;; TODO:
;; - heatpump.performance.thermalPower
;; - heatpump.performance.number
(define (storedata handle data)
  (let* ((system (safe-ref data "system"))
         (heatpump (safe-ref system "heatpump"))
         (heatpump-active (safe-ref heatpump "active"))
         (heatpump-temps (safe-ref heatpump "temperatures"))
         (heatpump-flow (safe-string->number (safe-ref heatpump-temps "flow")))
         (heatpump-return (safe-string->number (safe-ref heatpump-temps "return")))
         (heatpump-source-in (safe-ref (safe-ref (safe-ref heatpump "source") "temperatures") "in"))
         (heatpump-source (safe-string->number heatpump-source-in))

         (heating-circuits (safe-ref system "heatingcircuit"))
         (heating (and (vector? heating-circuits) (> (vector-length heating-circuits) 0)
                       (vector-ref heating-circuits 0)))
         (heating-active (safe-ref heating "pumpActive"))
         (heating-temps (safe-ref heating "temperatures"))
         (heating-set (safe-string->number (safe-ref heating-temps "set")))
         (heating-actual (safe-string->number (safe-ref heating-temps "actual")))

         (freshwater (safe-ref system "freshwater"))
         (circulation-active (safe-ref (safe-ref freshwater "circulation") "active"))
         (freshwater-temps (safe-ref freshwater "temperatures"))
         (freshwater-top (safe-string->number (safe-ref freshwater-temps "top")))
         (freshwater-bottom (safe-string->number (safe-ref freshwater-temps "bottom")))

         (buffer-temp (safe-string->number
                       (safe-ref (safe-ref (safe-ref system "buffer") "temperatures") "heating"))))
    (dbi-query handle (format #f "insert into idm (time,
heatpump_active, heatpump_flow, heatpump_return, heatpump_source,
heating_active, heating_set, heating_actual,
circulation_active, freshwater_top, freshwater_bottom,
buffer
) values (now(),
~a, ~s, ~s, ~s,
~a, ~s, ~s,
~a, ~s, ~s,
~s
)"
                              (if heatpump-active "true" "false") heatpump-flow heatpump-return heatpump-source
                              (if heating-active "true" "false") heating-set heating-actual
                              (if circulation-active "true" "false") freshwater-top freshwater-bottom
                              buffer-temp))))

(define (init handle)
  (dbi-query handle "CREATE TABLE IF NOT EXISTS idm (
  time        TIMESTAMPTZ NOT NULL,

  heatpump_active boolean not null,
  heatpump_flow double precision not null,
  heatpump_return double precision not null,
  heatpump_source double precision not null,

  heating_active boolean not null,
  heating_set double precision not null,
  heating_actual double precision not null,

  circulation_active boolean not null,
  freshwater_top double precision not null,
  freshwater_bottom double precision not null,

  buffer double precision not null
   ) WITH (timescaledb.hypertable);"))

(define (observe cfg)
  (let ((host (or (assoc-ref cfg "host") "idm.fritz.box"))
        (password (assoc-ref cfg "password")))
    (let loop ((delay 5))
      (catch #t
        (lambda ()
          (with-websocket (uri-for host password)
                          (lambda (ws)
                            (with-dbi-handle cfg
                                             (lambda (handle)
                                               (init handle)
                                               (let poll ()
                                                 (guard (e (else
                                                            (log-error e)
                                                            (log-info "polling interrupted, closing websocket")))
                                                   (websocket-send ws
                                                                   (scm->json-string '(("controller" . "system")
                                                                                       ("command" . "overview"))))
                                                   (storedata handle (json-string->scm (websocket-receive ws))))
                                                 (sleep 10)
                                                 (poll)))))))
        (lambda (key . args)
          (log-error (make-condition key args))
          (log-info "reconnecting in ~as" delay)
          (sleep delay)
          (loop (min (* delay 2) 120)))))))
