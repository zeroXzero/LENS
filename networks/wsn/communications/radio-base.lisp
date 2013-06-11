(in-package :lens.wsn)

(deftype radio-control-command-name()
  '(member set-state set-mode set-tx-output set-sleep-level set-carrier-freq
          set-cca-threshold set-cs-interrupt-on set-cs-interrupt-off
          set-encoding))

(deftype radio-state () '(member rx tx sleep))

;; signals for statistic collection
(register-signal 'tx
                 "Transmissions")
(register-signal 'rx-succeed-no-interference
                 "Successfully Received packets")
(register-signal 'rx-succeed-interference
                 "Successfully Received packets despite interference")
(register-signal 'rx-fail-no-interference
                 "packets failed even without interference")
(register-signal 'rx-fail-interference
                 "packets failed with interference")
(register-signal 'rx-fail-sensitivity
                 "packets failed, below sensitivity")
(register-signal 'rx-fail-modulation
                 "packets failed, wrong modulation")
(register-signal 'rx-fail-no-rx-state
                 "packets failed, radio not in RX")

(defstruct custom-modulation ;; element for storing custom snrtober.
  (snr 0.0 :type double-float)
  (ber 0.0 :type double-float))

(deftype modulation-type() '(or symbol (array custom-modulation 1)))

(deftype collision-model-type()
  '(member
    no-interference-no-collisions
    simple-collision-model
    additive-interference-model
    complex-interference-model))

(deftype encoding-type() '(member nrz code-4b5b manchester secdec))

(defstruct rx-mode
  (name nil :type symbol)
  (data-rate 0.0 :type double-float)
  (modulation 'ideal :type modulation-type)
  (bits-per-symbol 1 :type fixnum)
  (bandwidth 0.0 :type double-float)
  (noise-bandwidth 0.0 :type double-float)
  (noise-floor 0.0 :type double-float)
  (sensitivity 0.0 :type double-float)
  (power 0.0 :type double-float))

(defstruct received-signal
  src ;; used to distingish between signals e.g. node or radio id
  (power-dbm 0.0 :type double-float)
  (modulation 'ideal :type modulation-type)
  (encoding 'nrz :type encoding-type)
  (current-interference 0.0 :type double-float) ;; in dbm
  (max-interference 0.0 :type double-float) ;; in dbm
  (bit-errors 0 :type (or fixnum t)))

(defstruct total-power-received
  (power-dbm 0.0 :type double-float)
  (start-time 0.0 :type time-type))

(defstruct transition-element
  (delay 0.0 :type time-type)
  (power 0.0 :type double-float)) ;; in mW

(defstruct sleep-level
  (name nil :type symbol)
  (power 0.0 :type double-float)
  (up (make-transition-element) :type (or transition-element nil))
  (down (make-transition-element) :type (or transition-element nil)))

(defstruct tx-level
  (output-power 0.0 :type double-float) ;; in dbm
  (power-consumed 0.0 :type double-float)) ;; in W

(deftype cca-result() '(member clear busy cs-not-valid cs-not-valid-yet))

(defclass radio(comms-module)
  ((address :parameter t :type integer :reader mac-address
            :documentation "MAC address - will default to node index.")
   (radio-parameters-file
    :parameter t :type string :reader radio-parameters-file
    :documentation "the file that contains most radio parameters")
   (initial-mode :parameter t :initform  nil :type symbol
         :documentation "we can choose an rx-mode to begin with. Modes are
         defined in the RadioParametersFile. nil means use
         the first mode defined)")
   (state :type symbol :parameter t :initform 'rx :accessor state
          :documentation "we can choose a radio state to begin
          with. RX and TX are always there. according to the radio
          defined we can choose from a different set of sleep states")
   (initial-tx-output-power
    :type double-float :parameter t :initform nil
    :documentation "we can choose a Txpower to begin with. Possible tx
    power values are defined in the RadioParametersFile. nil
    means use the first tx power defined (which is also the highest)")
   (initial-sleep-level
    :type symbol :parameter t :initform nil
    :documentation "we can choose a sleep level which will be used
    when a transition to SLEEP state is requested. nil means
    use first level defined (will usually be the fastest and most
    energy consuming sleep state)")
   (carrier-frequency
    :type double-float :parameter t :initform 2.4E9 :accessor carrier-frequency
    :properties (:units "Hz")
    :documentation "the carrier frequency (in Hz) to begin with.")
   (encoding :type encoding-type :reader encoding)
   (collision-model
    :type symbol :parameter t :initform 'additive-interference-model
    :reader collision-model
    :documentation "none, simple, additive or advance interference")
   (cca-threshold
    :type real :parameter t :initform -95 :accessor cca-threshold
    :documentation "the threshold of the RSSI register (in dBm) were
    above it channel is NOT clear")
   (symbols-for-rssi
    :type integer :parameter t :initform 8 :reader symbols-for-rssi)
   (carrier-sense-interrupt-enabled
    :type boolean :parameter t :initform nil
    :reader carrier-sense-interrupt-enabled)
   (max-phy-frame-size
    :initform 1024 :type integer :parameter t :reader max-phy-frame-size
    :properties (:units "B") :documentation "in bytes")
   (header-overhead :initform 6 :documentation "in bytes - 802.15.4=6bytes")
   (avg-busy-frame
    :type double-float :initform 1 :parameter t :reader avg-busy-frame
    :properties (:units "s")
    :documentation "integration time for measuring avg busy time")
   (avg-busy :type double-float :initform 0 :accessor avg-busy)
   (buffer-size :initform 16) ;; overwrite inherited default
   (wireless-channel :type gate :reader wireless-channel
                     :documentation "Gate to directly send wireless messages
               to. Messages from the wireless layer will be send
               direct to fromWireless input gate in radio module")
   ;; these are derived from radio-parameters file or ini file
   (tx-levels :type sequence :reader tx-levels)
   (rx-modes :type sequence :reader rx-modes)
   (sleep-levels :initform nil :type sequence :reader sleep-levels)
   (transitions
    :type list :reader transitions
    :documentation "Power and delay for transitions between states stored in p-list of p-lists - access is (getf (getf args to) from)")
   (tx-level :type tx-level :accessor tx-level)
   (rx-mode :type rx-mode :accessor rx-mode)
   (sleep-level :type sleep-level :accessor sleep-level)
   (last-transition-time
    :type time-type :initform 0.0 :accessor last-transition-time)
   (changing-to-state
    :type radio-state :initform nil :accessor changing-to-state
    :documentation "indicates that the Radio is in the middle of changing to
							a new state")
   (received-signals
    :initform nil :type list :accessor received-signals
    :documentation " a list of signals curently being received")
   (time-of-last-signal-change
    :initform 0.0 :type time-type :accessor time-of-last-signal-change
    :documentation "last time the above list changed")
   (total-power-received
    :initform nil :type list :accessor total-power-received
    :documentation " a history of recent changes in total received power to help calculate RSSI")
   (rssi-integration-time
    :initform 1.0 :type time-type :reader rssi-integration-time
    :documentation "span of time the total received power is integrated to calculate RSSI")
   (cs-interrupt-message
    :type radio-control-message :reader cs-interrupt-message
    :initform (make-instance 'radio-control-message
                             :command 'carrier-sense-interrupt)
    :documentation " message that carries a future carrier sense interrupt")
   (state-transition-message
    :type message :reader state-transition-message
    :initform (make-instance 'message :name 'state-transition)
    :documentation "Self message to complete state transmisition")
   (continue-tx-message
    :type message :reader continue-tx-message
    :initform (make-instance 'message :name 'radio-continue-tx)
    :documentation "Self message to continue transmitting")
   (state-after-tx :initform 'rx :type radio-state :accessor state-after-tx)
   (processing-delay
    :type time-type :initarg :processing-delay :parameter t
    :initform 0.00001 :reader processing-delay
    :documentation "delay to pass packets/messages/interrupts to upper layer"))
  (:gates
   (mac :inout)
   (fromWireless :input))
  (:properties
   :statistic (tx
               :title "Transmissions" :default (count))
   :statistic (rx-succeed-no-interference
               :title "Successfully Received packets"  :default (count))
   :statistic (rx-succeed-interference
               :title "Successfully Received packets despite interference"
               :default (count))
   :statistic (rx-fail-no-interference
               :title "packets failed even without interference"
               :default (count))
   :statistic (rx-fail-interference
               :title "packets failed with interference" :default (count))
   :statistic (rx-fail-sensitivity
               :title "packets failed, below sensitivity" :default (count))
   :statistic (rx-fail-modulation
               :title "packets failed, wrong modulation" :default (count))
   :statistic (rx-fail-no-rx-state
               :title "packets failed, radio not in RX" :default (count)))
  (:metaclass module-class))

(defmethod initialize-instance :after ((radio radio) &key &allow-other-keys)
  (parse-radio-parameter-file radio)
  (with-slots(initial-mode initial-tx-output-power initial-sleep-level
              rssi-integration-time) radio
    (setf (rx-mode radio)
          (or (find initial-mode (rx-modes radio) :key #'rx-mode-name)
              (elt (rx-modes radio) 0)))
    (setf (tx-level radio)
          (or (find initial-tx-output-power (tx-levels radio)
                    :key #'tx-level-output-power :test #'=)
              (elt (tx-levels radio) 0)))
    (setf (sleep-level radio)
          (or (find initial-sleep-level (sleep-levels radio)
                    :key #'sleep-level-name)
              (elt (sleep-levels radio) 0)))
    (setf rssi-integration-time
          (* (symbols-for-rssi radio)
             (/ (rx-mode-bits-per-symbol (rx-mode radio))
                (rx-mode-data-rate (rx-mode radio)))))
    (setf (last-transition-time radio) 0.0d0)))

(defmethod initialize((radio radio) &optional (stage 0))
  (case stage
    (0
     ;; determine address based on node index if undefined
     (unless (slot-boundp radio 'address)
       (setf (slot-value radio 'address) (nodeid (node radio))))
      ;; complete initialisation according to starting state
     (setf (changing-to-state radio) (state radio)
           (state radio) 'rx)
     (complete-state-transition radio)))
  (call-next-method))

(defmethod startup((radio radio))
  (setf (time-of-last-signal-change radio) (simulation-time))
  (push (make-total-power-received
         :start-time (simulation-time)
         :power-dbm (rx-mode-noise-floor (rx-mode radio)))
        (total-power-received radio)))

(defun parse-radio-parameter-file(radio)
  (let ((parameters
         (with-open-file(is (merge-pathnames (radio-parameters-file radio))
                            :direction :input :if-does-not-exist :error)
           (read is))))
    (dolist(record parameters)
      (let((args (rest record)))
        (assert (not (slot-boundp radio (car record)))
                ()
                "Duplicate ~A specification in radio parameters file" (car record))
        (ecase (car record)
          (rx-modes
           (assert (every #'rx-mode-p args)
                   ()
                   "Invalid rx modes specification in radio parameters file")
           (setf (slot-value radio 'rx-modes) args))
          (tx-levels
           (assert (every #'tx-level-p args)
                   ()
                   "Invalid tx levels specification in radio parameters file")
           (setf (slot-value radio 'tx-levels) args))
          (sleep-levels
           (assert (every #'sleep-level-p args)
                   ()
                   "Invalid sleep levels specification in radio parameters file")
           (setf (slot-value radio 'sleep-levels) args))
          (transitions
           (let ((sec (load-time-value '(rx tx sleep))))
             (loop :for to :in sec
                :do (loop :for from in sec
                       :unless (eql from to)
                       :do (let ((e (getf (getf args to) from)))
                             (assert (transition-element-p e)
                               ()
                               "Invalid state transition ~A in radio parameters file" e)))))
           (setf (slot-value radio 'transitions) args)))))))

(defun update-received-signals(radio interferance)
  "Update current interference and bit errors in received signals"
  (dolist(signal (received-signals radio))
    (let ((bit-errors (received-signal-bit-errors signal))
          (max-errors (max-errors-allowed
                       radio (received-signal-encoding signal))))
      ;; only need to update bit-errors for an element that will be received
      (when (and (numberp bit-errors) (<= bit-errors max-errors))
        (let ((num-of-bits
               (ceiling (* (rx-mode-data-rate (rx-mode radio))
                           (- (simulation-time)
                              (time-of-last-signal-change radio)))))
              (ber (snr2ber (rx-mode radio)
                            (- (received-signal-power-dbm signal)
                               (received-signal-current-interference signal)))))
          (incf (received-signal-bit-errors signal)
                (bit-errors ber num-of-bits max-errors)))
        ;; update current-interference in the received signal structure
        (unless (eql signal interferance)
          (update-interference radio signal interferance))))))

(defmethod handle-message((radio radio) (message wireless-signal-start))
  ;; if carrier doesn't match ignore messge - may want to calculate
  ;; spectral overlap interference in future taking account of bandwidth
  (unless (= (carrier-frequency radio) (carrier-frequency message))
    (return-from handle-message))
  ;; if we are not in RX state or we are changing state, then process
  ;; the signal minimally. We still need to keep a list of signals
  ;; because when we go back in RX we might have some signals active
  ;; from before, acting as interference to the new (fully received
  ;; signals)
  (when (or (changing-to-state radio) (not (eql (state radio) 'rx)))
    (push
     (make-received-signal
      :src (src message)
      :power-dbm (power-dbm message)
      :bit-errors t)
     (received-signals radio))
    (emit radio 'rx-fail-no-rx-state)
    (return-from handle-message))
  ;; If we are in RX state, go throught the list of received signals
  ;; and update bit-errors and current-interference
  (update-received-signals radio message)
  ;;insert new signal in the received signals list
  (let* ((rx-mode (rx-mode radio))
         (new-signal
          (make-received-signal
           :src (src message)
           :power-dbm (power-dbm message)
           :modulation (modulation message)
           :encoding (encoding message)
           :current-interference
           (ecase (collision-model radio)
             (no-interference-no-collisions
              (rx-mode-noise-floor rx-mode))
             (additive-interference-model ;; the default
              (total-power-received-power-dbm
               (first (total-power-received radio))))
             (simple-collision-model
              ;; if other received signals are larger than the noise floor
					    ;; then this is considered catastrophic interference.
              (if (> (total-power-received-power-dbm
                      (first (total-power-received radio)))
                     (rx-mode-noise-floor rx-mode))
                  0.0d0 ;; a large value in dBm
                  (rx-mode-noise-floor rx-mode))))))
         #+nil(complex-interference-model ;; not implemented
               (rx-mode-noise-floor (rx-mode radio))))
    (setf (received-signal-max-interference new-signal)
          (received-signal-current-interference new-signal))
    (when (not (eql (rx-mode-modulation rx-mode)
                    (received-signal-modulation new-signal)))
      (setf (received-signal-bit-errors new-signal) t)
      (emit radio 'rx-fail-modulation))
    (when (< (received-signal-power-dbm new-signal)
             (rx-mode-sensitivity rx-mode))
      (setf (received-signal-bit-errors new-signal) t)
      (emit radio 'rx-fail-sensitivity))
    (push new-signal (received-signals radio))
    (update-total-power-received radio (received-signal-power-dbm new-signal))
    (when (and (carrier-sense-interrupt-enabled radio)
               (> (received-signal-power-dbm new-signal) (cca-threshold radio)))
      (update-possible-cs-interrupt radio))
    (setf (time-of-last-signal-change radio) (simulation-time))))

(defmethod handle-message((radio radio) (message wireless-signal-end))
  (let ((ending-signal (find (src message) (received-signals radio)
                             :key #'received-signal-src)))
    (unless ending-signal
      (eventlog "End signal ignored - mo matching start signal, probably due to carrier frequency change")
      (return-from handle-message))
    ;; if not in RX state or are changing state just delete signal
    (when (or (changing-to-state radio) (not (eql (state radio) 'rx)))
      (when (numberp (received-signal-bit-errors ending-signal))
        (emit radio 'rx-fail-no-rx-state))
      (setf (received-signals radio)
            (delete ending-signal (received-signals radio)))
      (return-from handle-message))
    ;; if in rx state update received signals
    (update-received-signals radio ending-signal)
    (update-total-power-received radio ending-signal)
    (setf (time-of-last-signal-change radio) (simulation-time))
    (when (numberp (received-signal-bit-errors ending-signal))
      (cond
        ((<= (received-signal-bit-errors ending-signal)
             (max-errors-allowed
              radio (received-signal-encoding ending-signal)))
         (let* ((mac-pkt (decapsulate message))
                (info (control-info mac-pkt)))
           (setf (rssi info) (read-rssi radio)
                 (lqi info)
                 (- (received-signal-power-dbm ending-signal)
                    (received-signal-max-interference ending-signal)))
           (send radio mac-pkt 'mac :delay (processing-delay radio)))
         (if (= (received-signal-max-interference ending-signal)
                (rx-mode-noise-floor (rx-mode radio)))
             (emit radio 'rx-succeed-no-interference)
             (emit radio 'rx-succeed-interference)))
        ((= (received-signal-max-interference ending-signal)
            (rx-mode-noise-floor (rx-mode radio)))
         (emit radio 'rx-fail-no-interference))
        (t (emit radio 'rx-fail-interference))))
    (setf (received-signals radio)
          (delete ending-signal (received-signals radio)))))

(defmethod handle-message((radio radio) (packet mac-packet))
  (when (and (> (max-phy-frame-size radio) 0)
             (> (+ (byte-length packet) (header-overhead radio))
                (max-phy-frame-size radio)))
    (eventlog
     "WARNING: MAC set to radio an oversized packet of ~A bytes. Packet Dropped"
     (+ (byte-length packet) (header-overhead radio)))
    (return-from handle-message))
  (unless (enqueue packet (buffer radio))
    (send radio
          (make-instance 'radio-control-message :name 'radio-buffer-full)
          'mac :delay (processing-delay radio))
    (eventlog "WARNING: Buffer FULL, discarding ~A" packet)))

(defmethod handle-message((radio radio) (message radio-control-message))
  ;; A self-(and external) message used for carrier sense interrupt.
	;; Since carrier sense interrupt is recalculated and rescheduled
	;; each time the signal is changed, it is important to be able to
	;; cancel an existing message if necessary. This is only possible
	;; for self messages. So radio will schedule CS interrupt message
	;; as a self event, and when it fires (i.e. not cancelled), then
	;; the message can just be forwarded to MAC. NOTE the 'return'
	;; to avoid message deletion in the end;
  (send radio message 'mac))

(defmethod handle-message((radio radio) (message radio-control-command))
  (ecase (command message)
    (set-state
     (check-type (argument message) radio-state)
     ;; The command changes the basic state of the radio. Because of
		 ;; the transition delay and other restrictions we need to create a
		 ;; self message and schedule it in the apporpriate time in the future.
		 ;; If we are in TX, not changing, and this is an external message
		 ;; then we DO NOT initiate the change process. We just set the
		 ;; variable stateAfterTX, and we let the RADIO_CONTINUE_TX code
		 ;; to handle the transition, when the TX buffer is empty.
     (with-slots(state changing-to-state) radio
     ;; If we are asked to change to the current (stable) state,
     ;; or the state we are changing to anyway, do nothing
       (when (eql (argument message) (or changing-to-state state))
         (return-from handle-message))
     ;; If we are asked to change from TX, and this is an external
     ;; command, and we are not changing already, then just record the
     ;; intended target state. Otherwise proceed with the change.
     (when (and (eql state 'tx) (not (self-message-p message))
                (not changing-to-state))
       (setf (state-after-tx radio) (argument message))
       (return-from handle-message))
     (setf changing-to-state (argument message))
     (let* ((transition
             (getf (getf (transitions radio) changing-to-state) state))
            (transition-delay (transition-element-delay transition))
            (transition-power (transition-element-power transition)))
       ;; With sleep levels it gets a little more complicated. We
			 ;; can add the trans delay from going to one sleep level to the
			 ;; other to get the total transDelay, but the power is not as
			 ;; easy. Ideally we would schedule delayed powerDrawn messages
			 ;; as we get from one sleep level to the other, but what
			 ;; happens if we receive another state change message? We would
			 ;; have to cancel these messages. Instead we are calculating
			 ;; the average power and sending one powerDrawn message. It
			 ;; might be a little less accurate in rare situations (very
			 ;; fast state changes), but cleaner in implementation.
       (flet((accumulate-level(level direction)
               (let* ((transition (funcall direction level))
                      (level-delay (transition-element-delay transition))
                      (level-power (transition-element-power transition)))
                 (setf transition-power
                      (/ (+ (* transition-power transition-delay)
                            (* level-power level-delay))
                         (+ transition-delay level-delay))
                      transition-delay
                      (+ transition-delay level-delay)))))
         (cond
           ((eql state 'sleep)
            (loop :for a :on (reverse (sleep-levels radio))
               :until (eql (car a) (sleep-level radio))
               :finally
               (loop :for b :on a
                  :do (accumulate-level (car b) #'sleep-level-up))))
           ((eql changing-to-state 'sleep)
            (loop :for a :on (sleep-levels radio)
               :until (eql (car a) (sleep-level radio))
               :do (accumulate-level (car a) #'sleep-level-down)))))
       (emit radio 'power-drawn transition-power)
       (eventlog "Set state to ~A, delay=~A, power=~A"
                 changing-to-state transition-delay transition-power)
       (delay-state-transition radio transition-delay))))

    ;; For the rest of the control commands we do not need to take any
    ;; special measures, or create new messages. We just parse the
    ;; command and assign the new value to the appropriate variable. We
    ;; do not need to change the drawn power, or otherwise change the
    ;; current behaviour of the radio. If the radio is transmiting we
    ;; will continue to TX with the old power until the buffer is
    ;; flushed and we try to TX again. If we are sleeping and change the
    ;; sleepLevel, the power will change the next time to go to
    ;; sleep. Only exception is RX mode where we change the power drawn,
    ;; even though we keep receiving currently received signals as with
    ;; the old mode. We could go and make all bitErrors = ALL_ERRORS,
    ;; but not worth the trouble I think.

    (set-mode
     (with-slots(rx-mode rx-modes rssi-integration-time symbols-for-rssi state)
         radio
       (setf rx-mode (find (argument message) rx-modes :key #'rx-mode-name))
       (assert rx-mode()
               "No radio mode named ~A found" (argument message))
       (eventlog "Changed rx mode to ~A" rx-mode)
       (setf rssi-integration-time
             (* symbols-for-rssi
                  (/ (rx-mode-bits-per-symbol rx-mode)
                     (rx-mode-data-rate rx-mode))))
       ;; if in rx mode change drawn power
       (when (eql state 'rx)
         (emit radio 'power-drawn (rx-mode-power rx-mode)))))

    (set-tx-output
     (with-slots(tx-level tx-levels) radio
       (setf tx-level (find (argument message) tx-levels
                            :key #'tx-level-output-power))
       (assert tx-level ()
               "Invalid tx output power level ~A" (argument message))
       (eventlog "Changed TX power output to ~A dBm consuming ~A W"
                 (tx-level-output-power tx-level)
                 (tx-level-power-consumed tx-level))))

    (set-sleep-level
     (with-slots(sleep-level sleep-levels) radio
       (setf sleep-level (find (argument message) sleep-levels
                               :key #'sleep-level-name))
       (assert sleep-level ()
               "Invalid sleep level ~A" (argument message))
       (eventlog "Changed default sleep level to ~A"
                 (sleep-level-name sleep-level))))

    (set-carrier-freq
     (with-slots(carrier-frequency) radio
       (setf carrier-frequency (argument message))
       (eventlog "Changed carrier frequency to ~A Hz" carrier-frequency)
       ;; clear received signals as they are no longer valid and don't create
       ;; interference with the new incoming signals
       (setf (received-signals radio) nil)))

    (set-cca-threshold
     (with-slots(cca-threshold) radio
       (setf cca-threshold (argument message))
       (eventlog "Changed CCA threshold to ~A dBm" cca-threshold)))

    (set-cs-interrupt-on
     (setf (slot-value radio 'carrier-sense-interrupt-enabled) t)
     (eventlog "CS interrupt turned ON"))

    (set-cs-interrupt-off
     (setf (slot-value radio 'carrier-sense-interrupt-enabled) nil)
     (eventlog "CS interrupt turned OFF"))

    (set-encoding
     (with-slots(encoding) radio
       (check-type (argument message) encoding-type)
       (setf encoding (argument message))))))

(defun delay-state-transition(radio delay)
  (let ((msg (state-transition-message radio)))
    (when (scheduled-p msg)
      (eventlog "WARNING: command to change to a new state was received before previous state transition was completed")
      (cancel msg))
    (schedule-at radio msg :delay delay)))

(defun complete-state-transition(radio)
  (with-slots(state changing-to-state last-transition-time
                    avg-busy avg-busy-frame) radio
    (when (and (or (eql changing-to-state 'sleep) (eql state 'sleep))
               (not (eql state changing-to-state)))
      (let* ((now (simulation-time))
             (ratio (min 1 (/ (- now last-transition-time) avg-busy-frame))))
        (setf avg-busy (* avg-busy (1- ratio)))
        (when (not (eql state 'sleep))
          (incf avg-busy ratio))
        (setf last-transition-time now)))
    (setf state changing-to-state)
    (eventlog "completing transition to ~A" state)
    (setf changing-to-state nil)
    (ecase state
      (tx
       (cond
         ((empty-p (buffer radio))
          ;; just changed to TX but buffer empty so send command to change to rx
          (schedule-at radio
                       (make-instance 'radio-command-message
                                      :command 'set-state
                                      :argument 'rx))
          (eventlog "WARNING: just changed to TX but buffer is empty - changing to RX"))
         (t
          (let ((time-to-tx-packet (debuffer-and-send radio)))
            (emit radio 'power-drawn (tx-level-power-consumed (tx-level radio)))
            ;; flush received power history
            (setf (total-power-received radio) nil)
            (schedule-at radio (continue-tx-message radio)
                         :delay time-to-tx-packet)))))
      (rx
       (emit radio 'power-drawn (rx-mode-power (rx-mode radio)))
       (update-total-power-received radio nil))
      (sleep
       (emit radio 'power-drawn (sleep-level-power (sleep-level radio)))
       (setf (total-power-received radio) nil)))))

(defmethod handle-message((radio radio) (message message))
  (cond
    ((eql message (state-transition-message radio))
     (complete-state-transition radio))
    ((eql message (continue-tx-message radio))
     (radio-continue-tx radio))
    (t (call-next-method))))

(defun radio-continue-tx(radio)
;; TODO
  (cond
    ((empty-p (buffer radio))
     ;; buffer empty so send command to change to rx
     (schedule-at radio
                  (make-instance 'radio-command-message
                                 :command 'set-state
                                 :argument (state-after-tx radio)))
     (eventlog "TX finished - changing to ~A" (state-after-tx radio))
     (setf (state-after-tx radio) 'rx)) ;; return to default behaviour
    (t
     (let ((time-to-tx-packet (debuffer-and-send radio)))
       (emit radio 'power-drawn (tx-level-power-consumed (tx-level radio)))
       ;; flush received power history
       (setf (total-power-received radio) nil)
       (schedule-at radio (continue-tx-message radio)
                    :delay time-to-tx-packet)))))

(defun debuffer-and-send(radio)
  (let* ((mac-pkt (dequeue (buffer radio)))
         (begin
          (make-instance 'wireless-signal-start
                         :src (node radio)
                         :power-dbm (tx-level-output-power (tx-level radio))
                         :carrier-frequency (carrier-frequency radio)
                         :bandwidth (rx-mode-bandwidth (rx-mode radio))
                         :modulation (rx-mode-modulation (rx-mode radio))
                         :encoding (encoding radio)))
         (end (make-instance 'wireless-signal-end
                             :src (node radio)
                             :byte-length (header-overhead radio))))
    (encapsulate end mac-pkt)
    (let ((tx-time (/ (bit-length end) (rx-mode-data-rate (rx-mode radio)))))
      (send radio begin (wireless-channel radio))
      (send radio end (wireless-channel radio) :delay tx-time)
      (emit radio 'tx)
      (eventlog "Sending packet, transmission will last ~A secs" tx-time)
      tx-time)))

(defgeneric update-total-power-received(radio value)
  (:documentation "Update the history of total power received."))

(defmethod update-total-power-received(radio (new-power number))
  (push
   (make-total-power-received
    :start-time (simulation-time)
    :power-dbm (dbm+ (total-power-received-power-dbm
                      (first (total-power-received radio)))
                     new-power))
   (total-power-received radio)))

(defmethod update-total-power-received(radio (ending-signal received-signal))
  (push
   (make-total-power-received
    :start-time (simulation-time)
    :power-dbm (reduce #'dbm+ (received-signals radio)
                       :key #'received-signal-power-dbm
                       :initial-value (rx-mode-noise-floor (rx-mode radio))))
   (total-power-received radio)))

(defmethod update-total-power-received(radio (dummy (eql nil)))
  (let((p (rx-mode-noise-floor (rx-mode radio))))
    (dolist(received-signal (received-signals radio))
      (setf p (dbm+ p (received-signal-power-dbm received-signal)))
      (when (numberp (received-signal-bit-errors received-signal))
        (setf (received-signal-bit-errors received-signal) t)
        (emit radio 'rx-fail-no-rx-state)
        (eventlog "Just entered RX, existing signal from ~A cannot be received." (src received-signal))))
    (push
     (make-total-power-received
      :start-time (simulation-time)
      :power-dbm p)
     (total-power-received radio))))

(defgeneric update-interference(radio received-signal arg)
  (:documentation " Update interference of one element in the
  receivedSignals list."))

(defmethod update-interference
    (radio (received-signal received-signal) (msg wireless-signal-start))
  (ecase (collision-model radio)
    (no-interference-no-collisions );; do nothing
    (simple-collision-model
     ;; an arbritrary rule: if the signal is more than 6dB less than
     ;; sensitivity, intereference is considered catastrophic.
     (when (> (power-dbm msg) (- (rx-mode-sensitivity (rx-mode radio)) 6.0))
       ;; corrupt signal and set interference to a large value
       (setf (received-signal-bit-errors received-signal)
             (1+ (max-errors-allowed
                  radio
                  (received-signal-encoding received-signal)))
             (received-signal-max-interference received-signal) 0.0)))
    (additive-interference-model
     (setf (received-signal-current-interference received-signal)
           (dbm+
            (received-signal-current-interference received-signal)
            (power-dbm msg)))
     (setf (received-signal-max-interference received-signal)
           (max (received-signal-current-interference received-signal)
                (received-signal-max-interference received-signal))))
    #+nil(complex-interference-model )))

(defmethod update-interference
    (radio (remaining-signal received-signal) (ending-signal received-signal))
  (ecase (collision-model radio)
    (no-interference-no-collisions );; do nothing
    (simple-collision-model
     ;; do nothing - this signal corrupted/destroyed other signals already
     )
    (additive-interference-model
     (setf (received-signal-current-interference remaining-signal)
           (rx-mode-noise-floor (rx-mode radio)))
     (dolist(it (received-signals radio))
       (unless (or (eql it remaining-signal) (eql it ending-signal))
         (setf (received-signal-current-interference remaining-signal)
               (dbm+
                (received-signal-current-interference remaining-signal)
                (received-signal-current-interference it))))))
    #+nil(complex-interference-model )))

(defun read-rssi(radio)
  ;;if we are not RXing return the appropriate error code
  (unless (eql (state radio) 'rx) (return-from read-rssi 'cs-not-valid))
  (let* ((rssi -200.0) ;; a very small value
         (current-time (simulation-time))
         (rssi-integration-time (rssi-integration-time radio))
         (limit-time (- current-time rssi-integration-time)))
    (do*((remaining (total-power-received radio) (cdr remaining)))
        ((or (<= current-time limit-time) (not remaining))
         (progn
           ;; if not rx long enough return error code
           (when (> current-time limit-time)
             (return-from read-rssi 'cs-not-valid-yet))
           (when (<= rssi-integration-time 0)
             ;; special case for naive model - current total signal power returned
             (setf rssi (total-power-received-power-dbm (car remaining)))
             (setf remaining (cdr remaining)))
           ;; erase rest of elements that are out of date
           (when remaining (setf (cdr remaining) nil))
           rssi))
      (let* ((it (car remaining))
             (fraction-time (- current-time
                               (/ (max (total-power-received-start-time it)
                                       limit-time)
                                  rssi-integration-time))))
        (setf rssi (dbm+ (+ (total-power-received-power-dbm it)
                            (ratio-to-db fraction-time))
                         rssi))
        (setf current-time  (total-power-received-start-time it))))))

(defun update-possible-cs-interrupt(radio)
 ;; A method to calculate a possible carrier sense in the future and
 ;; schedule a message to notify layers above. Since the received
 ;; power history is expressed in dBm, exact computations are
 ;; complex. Instead we assume that all previous received power is
 ;; negligibly small and given the current power, CCAthreshold and
 ;; averaging/integration time for RSSI.
  (when (> (read-rssi radio) (cca-threshold radio))
    ;; if we are above the threshold, no point in scheduling an interrupt
    (return-from update-possible-cs-interrupt))
  ;;if we are going to schedule an interrupt, cancel any future CS interrupt
  (cancel (cs-interrupt-message radio))
  ;; We calculate the fraction of the RSSI averaging time that it
  ;; will take for the current power to surpass the CCA
  ;; threshold. This is based on how many times larger is the
  ;; current time from the CCAthreshold. E.g., if it is 2 times
  ;; larger the fraction is 1/2, if it is 8, the fraction is 1/8
  (let ((fraction-time
         (/ 1.0d0
            (db-to-ratio
             (- (total-power-received-power-dbm
                 (car (total-power-received radio)))
                (cca-threshold radio))))))
	;;  we might adjust the fraction based on symbolsForRSSI. E.g. if
	;; symbolsForRSSI is 4 and we get 1/8 then we might adjust it to
	;; 1/4. We do not have enough  details for the RSSI model
	;; calculation though.

	;; // schedule message
    (schedule-at radio (cs-interrupt-message radio)
                 :delay (+ (processing-delay radio)
                           (* fraction-time (rssi-integration-time radio))))))

(defmethod snr2ber(rx-mode snr-db &optional bpnb)
  (declare (ignore bpnb) (double-float snr-db))
  (snr2ber (modulation rx-mode) snr-db
           (/ (rx-mode-data-rate rx-mode)
              (rx-mode-noise-bandwidth rx-mode))))

(defun is-channel-clear(radio)
  (let ((value (read-rssi radio)))
    (if (symbolp value)
        value
        (if (< value (cca-threshold radio)) t nil))))

(defun bit-errors(ber num-of-bits max-bit-errors-allowed)
  (flet((prob(n) (probability-of-exactly-n-errors ber n num-of-bits)))
    (do*((bit-errors 0 (1+ bit-errors))
        (prob (prob bit-errors) (prob bit-errors))
        (c 0.0)) ;cumulativeProbabilityOfUnrealizedEvents
       ((or (= bit-errors max-bit-errors-allowed)
            (<= (lens::%gendblrand 0) (/ prob (- 1.0 c))))
        (if (= bit-errors max-bit-errors-allowed) (1+ bit-errors) bit-errors))
      (setf c (+ c prob)))))

(defgeneric max-errors-allowed(radio encoding)
  (:documentation "Return the maximum number of bit errors acceptable for given encoding")
  (:method(radio encoding)
    (declare (ignore radio encoding))
    0))


(defun max-tx-power-consumed(radio)
  (reduce #'max (mapcar #'tx-level-power-consumed (tx-levels radio))))
