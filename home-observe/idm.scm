(define-module (home-observe idm)
  #:use-module (dbi dbi)
  #:use-module (home-observe util)
  #:use-module (ice-9 iconv)
  #:use-module (json)
  #:use-module (srfi srfi-34)
  #:use-module (web socket client)
  #:export (observe))

(define upstream "ws://idm.fritz.box:61220/?auth_code=~a")

(define (with-websocket uri thunk)
  (let ((ws #f))
    (dynamic-wind
      (lambda ()
        (set! ws (open-websocket-for-uri uri))
        (format #t "~s~%" (websocket-receive ws)))
      (lambda ()
        (thunk ws))
      (lambda ()
        (close-websocket ws)))))

(define (storedata handle data)
  (let* ((system (assoc-ref data "system"))
         (heatpump (assoc-ref system "heatpump"))
         (heatpump-active (assoc-ref heatpump "active"))
         (heatpump-flow (string->number (assoc-ref (assoc-ref heatpump "temperatures") "flow")))
         (heatpump-return (string->number (assoc-ref (assoc-ref heatpump "temperatures") "return")))
         (heatpump-source (string->number (assoc-ref (assoc-ref (assoc-ref heatpump "source") "temperatures") "in")))

         (heating (vector-ref (assoc-ref system "heatingcircuit") 0))
         (heating-active (assoc-ref heating "pumpActive"))
         (heating-set (string->number (assoc-ref (assoc-ref heating "temperatures") "set")))
         (heating-actual (string->number (assoc-ref (assoc-ref heating "temperatures") "actual")))

         (freshwater (assoc-ref system "freshwater"))
         (circulation-active (assoc-ref (assoc-ref freshwater "circulation") "active"))
         (freshwater-top (string->number (assoc-ref (assoc-ref freshwater "temperatures") "top")))
         (freshwater-bottom (string->number (assoc-ref (assoc-ref freshwater "temperatures") "bottom")))

         (buffer-temp (string->number (assoc-ref (assoc-ref (assoc-ref system "buffer") "temperatures") "heating"))))
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
                              (if heatpump-active "true" "false") heatpump-flow heatpump-return heatpump-return
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
  (with-websocket (format #f upstream (assoc-ref cfg "password"))
                  (lambda (ws)
                    (with-dbi-handle cfg (lambda (handle)
                                           (init handle)
                                           (let loop ()
                                             (websocket-send ws
                                                             (scm->json-string '(("controller" . "system")
                                                                                 ("command" . "overview"))))
                                             (storedata handle (json-string->scm (websocket-receive ws)))
                                             (sleep 10)
                                             (loop)))))))
