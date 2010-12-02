;;; LENS System definition -*- Lisp -*-
;; $Id$
;; Copyright (C) 2007-2010 Dr. John A.R. Williams

;; Author: Dr. John A.R. Williams <J.A.R.Williams@jarw.org.uk>
;; Keywords:

;; This file is part of Lisp Educational Network Simulator (LENS)

;; This is free software released under the GNU General Public License (GPL)
;; See <http://www.gnu.org/copyleft/gpl.html>

;;; Commentary:

;;

;;; Code:

(in-package :cl-user)

(asdf:defsystem :lens
    :description "Lisp Educational Network Simulator (LENS)"
    :author "Dr. John A.R. Williams <J.A.R.Williams@aston.ac.uk>"
    :maintainer "Dr. John A.R. Williams <J.A.R.Williams@aston.ac.uk>"
    :licence "GPL v3"
    :long-description "A Network Simulator in LISP inspired by NS2 and GTNetS"
    :depends-on (:split-sequence :trivial-gray-streams :clrs :closer-mop)
    :components
    ((:module "core"
              :components
              ((:file "defpackage")
               (:file "common" :depends-on ("defpackage"))
               (:file "random" :depends-on ("defpackage"))
               (:file "compatibility" :depends-on ("defpackage"))
               (:file "scheduler" :depends-on
                      ("defpackage" "common" "compatibility"))
               (:file "packet" :depends-on ("defpackage" "scheduler"))
               (:file "address" :depends-on ("defpackage" "common"))
               (:file "packet-queue"
                      :depends-on ("defpackage" "common" "scheduler" "packet"
                                                "protocol"))
               (:file "protocol" :depends-on ("address" "common"))
               (:file "interface"
                      :depends-on ("defpackage" "packet-queue" "link"))
               (:file "trace" :depends-on
                      ("defpackage" "common" "scheduler" "compatibility"))
               (:file "routing" :depends-on ("common" "address"))
               (:file "node"
                       :depends-on ("common" "address" "protocol" "routing"))
               (:file "link"
                       :depends-on ("common" "scheduler" "random"
                                    "address" "packet-queue" "node"))
               (:file "application"
                       :depends-on ("common" "scheduler" "protocol"))
               #+nil(:file "statistics" :depends-on ("common" "scheduler"))


                (:file "user"
                       :depends-on ("common" "address" "scheduler" "link"
                                             "node"))))
))
     #+nil(:module "nodes" :depends-on ("core")
              :components
              ((:file "node")))
     #+nil(:module "links" :depends-on ("core")
              :components
              ((:file "p2p")
               (:file "ethernet")))
     #+nil(:module "applications" :depends-on ("core" "protocols" "routing")
              :components
              ((:file "cbr-source")
               (:file "udp-sink")
               (:file "tcp-source")
               (:file "tcp-server")))
     #+nil(:module "protocols" :depends-on ("core")
              :components
              ((:file "llcsnap")
               (:file "ieee802.3" :depends-on ("llcsnap"))
               (:file "defpackage")
               (:file "ipv4" :depends-on ("defpackage"))
               (:file "udp" :depends-on ("ipv4"))
               (:file "tcp" :depends-on ("ipv4"))
               (:file "icmp" :depends-on ("tcp"))
               (:file "tcp-tahoe" :depends-on ("tcp"))
               (:file "tcp-reno" :depends-on ("tcp"))
               (:file "tcp-newreno" :depends-on ("tcp-reno"))
               (:file "arp")))
     #+nil(:module "routing" :depends-on ("core")
              :components
              ((:file "dijkstra")
               (:file "manual")
               (:file "static" :depends-on ("manual" "dijkstra"))))
     #+nil(:module "graphics" :depends-on ("core")
              :components
              ((:file "defpackage")
               (:file "dot" :depends-on ("defpackage"))))))
