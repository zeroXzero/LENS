;; Network/Routing layer interface and base class
;; Copyright (C) 2014 Dr. John A.R. Williams

;; Author: Dr. John A.R. Williams <J.A.R.Williams@jarw.org.uk>
;; Keywords:

;;; Copying:

;; This file is part of Lisp Educational Network Simulator (LENS)

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; LENS is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:
(in-package :lens.wsn)

(defclass net-mac-control-info()
  ((RSSI :type double-float :initarg :RSSI :accessor RSSI :initform nil
         :documentation "the RSSI of the received packet")
   (LQI :type double-float :initarg :LQI :accessor LQI :initform nil
        :documentation "the LQI of the received packet")
   (next-hop :type integer :initarg :next-hop :accessor next-hop)
   (last-hop :type integer :initarg :last-hop :accessor last-hop))
  (:documentation "Information between routing and MAC
  which is external to but related to the packet i.e. not carried by a real
  packet (e.g., what is the next hop, or what was the RSSI for the
  packet received)."))

(defclass routing-packet(wsn-packet)
  ()
  (:documentation "A generic routing packet header. An app packet will
  be encapsulated in it. If definining your own routing protocol and
  need a more specialized packet you have to create one the extends
  this generic packet. [[to-mac]], [[enqueue]] and [[decapsulate]]
  specialisations provided. [[handle-message]] implementations which
  check destination address and forward to application and check frame
  size etc are provided. ."))

(defmethod print-object((p routing-packet) stream)
  (print-unreadable-object(p stream :type t)
     (when (slot-boundp p 'name)
      (format stream "~A " (name p)))
     (format stream "~A->~A (~D bytes)"
             (source p)
             (destination p)
             (byte-length p))))

;; Network_GenericFrame has the following real-world
;; (non-simulation-specific) fields:
;;    unsigned short int frameType; --> 2bytes
;;    string source;  ----------------> 2bytes
;;    string destinationCtrl; --------> 2bytes
;;    string lastHop; ------------> 2bytes
;;    string nextHop; ------------> 2bytes
;;    unsigned short int ttl; ----> 2bytes
;;    string applicationID; ------> 2bytes
;; Total bytes = 7*2 = 14 (|*|)
;; From these 14bytes, BypassRoutingModule doesn't use everything.
;; It doesn't use the ttl and applicationID fields.
;; Concluding the calculations, the Network_GenericFrame for
;; BypassRoutingModule has a total overhead of:
;; 14-(2+2) = 10 bytes

(defclass routing(comms-module)
  ((max-net-frame-size
    :initform 0 :type integer :parameter t :reader max-net-frame-size
    :properties (:units "B")
    :documentation "The maximum packet size the routing can handle in
    bytes (0 for no limit)"))
  (:gates
   (application :inout)
   (mac :inout))
  (:metaclass module-class)
  (:documentation "Base class for all routing modules. Base implementation Provides checking of maximum frame size allowed"))

(defmethod network-address((instance routing))
  (network-address (node instance)))

;; default - pass through unwanted control commands and messages -
;; warn if for this layer but unhandled
;; implementations must handle application packets and routing packets
;; by specialising handle-message main method

(defmethod handle-message((instance routing)
                          (message communications-control-command))
  (send instance message 'mac))

(defmethod handle-message((instance routing)
                          (message network-control-message))
  (warn 'unknown-message :module instance :message message))

(defmethod handle-message((instance routing)
                          (message communications-control-message))
  (send instance message 'application))

(defmethod handle-message((instance routing) (msg network-control-command))
  (handle-control-command instance (command msg) (argument msg)))

(defmethod node((instance comms-module)) (owner (owner instance)))

(defmethod handle-message :around ((module routing) (packet application-packet))
  (with-slots(max-net-frame-size header-overhead) module
    (if (and (> max-net-frame-size 0)
             (> (+ (byte-length packet) header-overhead) max-net-frame-size))
        (tracelog "Oversized packet ~A dropped. Size ~A, network layer overhead ~A, max network packet size ~A"
                  (byte-length packet) header-overhead max-net-frame-size)
        (progn
          (tracelog "Received ~A from application layer" packet)
          (call-next-method)))))

(defmethod  handle-message :before ((instance routing) (packet routing-packet))
  (tracelog "Received ~A from mac layer." packet))

(defmethod handle-message ((instance routing) (packet routing-packet))
  ;; from mac layer
  (when (or (eql (destination packet) (network-address (node instance)))
            (eql (destination packet) broadcast-network-address))
    (send instance (decapsulate packet) 'application)))

(defgeneric to-mac(routing entity &optional next-hop-mac-address)
  (:documentation "* Arguments

- routing :: a [[routing]] implementation
- entity :: a [[message]] or [[communications-control-command]]
- next-hop-mac-address :: MAC address for MAC layer to forward to

* Description

Send /entity/ from [[routing]] to [[mac]] layer module.")
  (:method((module routing) (command communications-control-command)
           &optional destination)
    (assert (and (not destination)
                 (not (typep command 'network-control-command))))
    (send module command 'mac))
  (:method((module routing) (packet routing-packet) &optional next-hop)
    (if next-hop
        (setf (control-info packet)
              (make-instance
               'net-mac-control-info
               :next-hop next-hop))
        (assert (next-hop (control-info packet))))
    (send module packet 'mac))
  (:method((module routing) (message message) &optional destination)
    (declare (ignore destination))
    (error "Network module ~A attempting to send ~A to mac"
           module message))
  (:method :before ((module routing) entity &optional destination)
    (declare (ignore destination))
    (tracelog "Sending ~A to MAC layer" entity)))

(defmethod decapsulate((packet routing-packet))
  (let ((application-packet (call-next-method)))
    (setf (control-info application-packet)
          (make-instance 'app-net-control-info
                         :rssi (rssi (control-info packet))
                         :lqi (lqi (control-info packet))
                         :source (source packet)
                         :destination (destination packet)))
    application-packet))

(defgeneric resolve-network-address(routing network-address)
  (:documentation "* Arguments

- routing :: a [[routing]] module
- network-address :: a network-address designator

* Description

Return resolved mac address from given network address")
  (:method(routing network-address)
    (declare (ignore routing))
    ;; by default mac address and network address have same values in WSN
    network-address))

(defmethod enqueue(packet (instance routing))
  (cond
    ((enqueue packet (buffer instance))
     ;; success
     (tracelog "Packet buffered from application layer, buffer state : ~D/~D"
               (size (buffer instance)) (buffer-size (buffer instance)))
     t)
    (t ;; failure
     (send instance
           (make-instance 'net-control-message :command 'net-buffer-full)
           'application)
     nil)))
