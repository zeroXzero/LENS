;; $Id$
;; IPv4 implementation
;; Copyright (C) 2006 Dr. John A.R. Williams

;; Author: Dr. John A.R. Williams <J.A.R.Williams@jarw.org.uk>
;; Keywords:

;; This file is part of Lisp Educational Network Simulator (LENS)

;; This is free software released under the GNU General Public License (GPL)
;; See <http://www.gnu.org/copyleft/gpl.html>

;;; Commentary:

;;

;;; Code:

(in-package :protocol.layer3)

(defparameter *default-ipv4-ttl* 64)
(defparameter *icmp-enabled-default* nil)

(defclass ipv4-header-option(pdu)
  ((option-number :type octet :initarg :option-number :reader option-number))
  (:documentation "The IP options part of the IP Header."))

(defmethod length-bytes((pdu ipv4-header-option)) 0)

(defmethod copy((pdu ipv4-header-option))
  (copy-with-slots pdu '(option-number)))

(defclass ipv4-header(pdu)
  ((name :initform "IP" :reader name :allocation :class)
   (trace-format
    :initform '((version "-~A") header-length service-type total-length
                identification flags fragment-offset ttl protocol-number
                (header-checksum "~4,'0X") src-address dst-address)
    :reader trace-format
    :allocation :class)
   (version :initarg :version :initform 4 :type octet :reader version
            :allocation :class)
   (service-type :initform 0 :type octet :reader servive-type
                 :reader packet:priority
                 :initarg :service-type)
   (total-length :initform 0 :type word :accessor total-length)
   (identification :initform 0 :type word)
   (flags :initform 0 :type octet)
   (fragment-offset :initform 0 :initarg :fragment-offset :type word)
   (ttl :initform *default-ipv4-ttl* :type octet :initarg :ttl :accessor ttl
        :documentation "Default ttl")
   (protocol-number
    :initform 17 :type octet :initarg :protocol-number
    :reader protocol-number
    :documentation "Protocol number for transport layer")
   (header-checksum :initform 0 :type word) ;; not used in simulation
   (src-address :type ipaddr :accessor src-address :initarg :src-address)
   (dst-address :type ipaddr :accessor dst-address :initarg :dst-address)
   (options :type list :accessor options :initform nil))
  (:documentation "The IP version 4 header"))

(defmethod length-bytes((pdu ipv4-header))
  (+ 20 (reduce #'+ (slot-value pdu 'options) :key #'length-bytes)))

(defmethod copy((h ipv4-header))
  (let ((copy
         (copy-with-slots
          h
          '(uid version service-type total-length identification
            flags fragment-offset ttl protocol header-checksum
            src-address dst-address))))
    (setf (slot-value copy 'options) (mapcar #'copy (options h)))
    copy))

(defclass ipv4(protocol)
  ((protocol-number :initform #x0800 :reader protocol-number
                    :allocation :class)
   (version :initform 4 :reader version :allocation :class)
   (route-locally :type boolean :initform nil :accessor route-locally
                  :documentation "Allows transport layer protocols on the same
node to communicate with each other.")
   (icmp-enabled :initform *icmp-enabled-default* :initarg :icmp-enabled
                 :reader icmp-enabled-p))
  (:documentation "IP v4 implementation"))

(register-protocol 'ipv4 #x0800)

(defmethod default-trace-detail((entity ipv4))
  '(ttl protocol-number src-address dst-address))

;; no state so do nothing - note it is intentional that there is no
;; default method here as every protocol should be considered on its
;; own merit.

(defmethod reset((ipv4 ipv4)))

(defmethod send((ipv4 ipv4) packet sender
                &key
                (src-address (network-address (node ipv4)))
                (dst-address :broadcast)
                (ttl *default-ipv4-ttl*)
                (tos 0)
                (fragment-offset 0)
                &allow-other-keys)
  (let ((iphdr (make-instance 'ipv4-header
                              :src-address src-address
                              :dst-address dst-address
                              :ttl ttl
                              :protocol-number (protocol-number sender)
                              :service-type tos
                              :fragment-offset fragment-offset))
        (node (node ipv4)))
    (push-pdu iphdr packet)
    (setf (total-length iphdr) (length-bytes packet))
  (cond
    ((broadcast-p dst-address) ;; broadcast address
     ;; if src-address is broadcast then all interfaces
     ;; else only interface(s) with given network address
     (pop-pdu iphdr)
     (map 'nil
          #'(lambda(interface)
              (when (and (up-p interface)
                   (or (broadcast-p src-address)
                       (address= (network-address interface) src-address)))
          (let ((iphdr (copy iphdr))
                (packet (copy packet)))
            (when (broadcast-p src-address)
              (setf (src-address iphdr)  (network-address interface)))
            (push-pdu iphdr packet)
            (send interface packet ipv4 :address :broadcast))))
          (interfaces node)))
    ((and (route-locally ipv4)
          (let ((interface (find-interface dst-address node)))
            (when interface
              ;; route locally - send back up stack
              (receive ipv4 packet interface)
              t))))
    (t ;; forward packet over interface
     (let ((route
            (getroute dst-address (routing node) :packet packet)))
       (when route
         (send (interface route) packet ipv4 :address (dst-address route))))))))

(defgeneric process-ip-option(option interface packet)
  (:documentation "Process an ip option")
  (:method(option interface packet)
    (error "Unknown IP option ~S" option)))

(defmethod receive((ipv4 ipv4) packet interface &key &allow-other-keys)
  "ipv4 data arrival"
  (let* ((node (node ipv4))
         (iphdr (pop-pdu packet))
         (dst-address (dst-address iphdr)))
      ;; process ip options
      (dolist(option (options iphdr))
        (process-ip-option option interface packet))
      (cond
        ((or (eql dst-address (network-address node))
             (find-interface dst-address node)
             (broadcast-p dst-address))
         ;; destined for this node
         (let ((proto (protocol-number iphdr)))
           (if (= proto (protocol-number 'icmp))
               (icmp-receive ipv4 packet iphdr)
               (let ((protocol (layer4:find-protocol proto node)))
                 (if protocol
                     (receive protocol packet ipv4 :src-address (src-address iphdr))
                     (progn
                       (drop ipv4 packet :text "L3-NP")
                       (destination-unreachable ipv4
                                       iphdr
                                        (pop-pdu packet)
                                       :code 'protocol-unreachable)))))))
        ((zerop (decf (ttl iphdr)))
         ;; TTL expired - drop, log and notify ICMP
         (drop ipv4 packet :text "L3-TTL")
         (time-exceeded ipv4 iphdr :code 'ttl-exceeded))
        (t
         (let ((route (getroute dst-address node :packet packet)))
           (cond
             ((not route) ;; can't route so drop it
              (drop ipv4 packet :text "L3-NR")
              (destination-unreachable ipv4
                                       iphdr (pop-pdu packet)
                                       :code 'host-unreachable))
             ((eql (interface route) interface) ;; routing loop - drop packet
              (drop ipv4 packet :text "L3-RL"))
             (t ;; forward to next hop
              (send (interface route) packet ipv4
                    :address (dst-address route)))))))))



;; (defmethod layer4:receive((demux ipv4-demux)
;;                                   node packet dst-address
;;                                   interface)
;;   (when (node:call-callbacks
;;            (layer demux) (protocol-number demux)
;;            :rx packet node interface)
;;     (let* ((pdu (peek-pdu packet))
;;            (layer4protocol
;;             (node:lookup-by-port (protocol-number pdu) node
;;                                  :local-port (dst-port pdu))))
;;       (cond
;;         (layer4protocol
;;          (layer4:receive
;;           layer4protocol node packet dst-address interface))
;;         (t ; no port - log and discard
;;          (write-trace node (ipv4)
;;                       :drop nil :packet packet :text "L3-NP")
;;          (destination-unreachable node packet
;;                                        (peek-pdu packet -1)
;;                                        pdu :port-unreachable))))))