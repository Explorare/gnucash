;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  qif-file.scm
;;;  read a QIF file into a <qif-file> object
;;;
;;;  Bill Gribble <grib@billgribble.com> 20 Feb 2000 
;;;  $Id$
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(gnc:support "qif-import/qif-file.scm")
(gnc:depend "qif-import/qif-objects.scm")
(gnc:depend "qif-import/qif-parse.scm")
(gnc:depend "qif-import/qif-utils.scm")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  qif-file:read-file self path  
;;  suck in all the transactions; if necessary, determine [guess]
;;  radix format first. 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (qif-file:read-file self path)
  (qif-file:set-path! self path)
  (let ((qstate-type #f)
        (current-xtn #f)
        (current-split #f)
        (current-account-name #f)
        (default-split #f)
        (first-xtn #f)
        (ignore-accounts #f)
        (line #f)
        (tag #f)
        (value #f)
        (heinous-error #f)
	(valid-acct-types 
         '(type:bank type:cash
                     type:ccard type:invst
                     #{type:oth\ a}#  #{type:oth\ l}#)))
    (with-input-from-file path
      (lambda ()        
        ;; loop over lines
        (let line-loop ()
          (set! line (read-delimited (string #\nl #\cr)))
          (if (and 
               (not (eof-object? line))
               (>= (string-length line) 1))
              (begin 
                ;; pick the 1-char tag off from the remainder of the line 
                (set! tag (string-ref line 0))
                (set! value (substring line 1 (string-length line)))
                
                ;; now do something with the line 
                (cond 
                 ;; the type switcher. 
                 ((eq? tag #\!)
                  (set! qstate-type (qif-file:parse-bang-field self value))
                  (cond ((member qstate-type valid-acct-types)
			 (set! current-xtn (make-qif-xtn))
			 (set! default-split (make-qif-split))
                         (qif-split:set-category! default-split "")
                         (qif-file:set-account-type! 
                          self (qif-file:state-to-account-type 
                                self qstate-type))
                         (set! first-xtn #t))
                        ((eq? qstate-type 'type:class)
                         (set! current-xtn (make-qif-class)))
                        ((eq? qstate-type 'type:cat)
                         (set! current-xtn (make-qif-cat)))
                        ((eq? qstate-type 'account)
                         (set! current-xtn (make-qif-acct)))
                        ((eq? qstate-type 'option:autoswitch)
                         (set! ignore-accounts #t))
                        ((eq? qstate-type 'clear:autoswitch)
                         (set! ignore-accounts #f))))

;;;                        (#t 
;;;                         (display "qif-file:read-file can't handle ")
;;;                         (write qstate-type)
;;;                         (display " transactions yet.")
;;;                         (newline))))
                 
                 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
                 ;; bank-account type transactions 
                 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
                 
                 ((member qstate-type valid-acct-types)
                  (case tag
                    ;; D : transaction date 
                    ((#\D)
                     (qif-xtn:set-date! current-xtn 
                                        (qif-file:parse-date self value)))
                    
                    ;; T : total amount 
                    ((#\T)
                     (qif-split:set-amount! 
                      default-split (qif-file:parse-value/decimal self value))
                     (if (not (number? (qif-split:amount default-split)))
                         (begin 
                           (display "value not a number : ")
                           (display value) (display " ")
                           (write (qif-split:amount default-split))
                           (newline))))
                    
                    ;; P : payee
                    ((#\P)
                     (qif-xtn:set-payee! current-xtn 
                                         (qif-file:parse-string self value)))
                    
                    ;; A : address 
                    ;; multiple "A" lines are appended together with 
                    ;; newlines; some Quicken files have a lot of 
                    ;; A lines. 
                    ((#\A)
                     (qif-xtn:set-address! 
                      current-xtn
                      (let ((current (qif-xtn:address current-xtn)))
                        (if (not (string? current))
                            (set! current ""))
                        (string-append 
                         current "\n"
                         (qif-file:parse-string self value)))))
                    
                    ;; N : check number / transaction number /xtn direction
                    ;; this could be a number or a string; no point in
                    ;; keeping it numeric just yet. 
                    ((#\N)
                     (qif-xtn:set-number! 
                      current-xtn (qif-file:parse-string self value)))
                    
                    ;; C : cleared flag 
                    ((#\C)
                     (qif-xtn:set-cleared! 
                      current-xtn (qif-file:parse-cleared-field self value)))
                    
                    ;; M : memo 
                    ((#\M)
                     (qif-split:set-memo! default-split
                                          (qif-file:parse-string self value)))
                    
                    ;; I : share price (stock transactions)
                    ((#\I)
                     (qif-xtn:set-share-price! 
                      current-xtn (qif-file:parse-value self value)))
                    
                    ;; Q : share price (stock transactions)
                    ((#\Q)
                     (qif-xtn:set-num-shares! 
                      current-xtn (qif-file:parse-value self value))
                     (qif-xtn:set-bank-xtn?! current-xtn #f))
                    
                    ;; Y : name of security (stock transactions)
                    ((#\Y)
                     (qif-xtn:set-security-name! 
                      current-xtn (qif-file:parse-string self value)))
                    
                    ;; O : adjustment (stock transactions)
                    ((#\O)
                     (qif-xtn:set-adjustment! 
                      current-xtn (qif-file:parse-value/decimal self value)))
                    
                    ;; L : category 
                    ((#\L)
                     (qif-split:set-category! 
                      default-split (qif-file:parse-string self value)))
                    
                    ;; S : split category 
                    ((#\S)
                     (set! current-split  (make-qif-split))
                     (qif-split:set-category! 
                      current-split (qif-file:parse-string self value))
                     (qif-xtn:set-splits! 
                      current-xtn
                      (cons current-split (qif-xtn:splits current-xtn))))
                    
                    ;; E : split memo (?)
                    ((#\E)
                     (qif-split:set-memo! 
                      current-split (qif-file:parse-string self value)))
                    
                    ;; $ : split amount (if there are splits)
                    ((#\$)
                     ;; if this is 'Type:Invst, I can't figure out 
                     ;; what the $ signifies.  I'll do it later. 
                     (if (not (eq? qstate-type 'type:invst))
                         (qif-split:set-amount! 
                          current-split 
                          (qif-file:parse-value/decimal self value))))
                    
                    ;; ^ : end-of-record 
                    ((#\^)
                     (if (qif-xtn:date current-xtn)
                         (begin 
                           (if (not (qif-split:amount default-split))
                               (qif-split:set-amount! default-split 0.00))
                           
                           (if (null? (qif-xtn:splits current-xtn))
                               (qif-xtn:set-splits! current-xtn
                                                    (list default-split)))
                           (if (and (not ignore-accounts)
                                    current-account-name)
                               (qif-xtn:set-from-acct! current-xtn 
                                                       current-account-name))
                           (qif-file:add-xtn! self current-xtn)))
;                         (begin
;                           (display "qif-file:read-file : discarding xtn")
;                           (newline)
;                           (qif-xtn:print current-xtn)))
                    
                     (if (and first-xtn
                              (string? (qif-xtn:payee current-xtn))
                              (string=? (qif-xtn:payee current-xtn)
                                        "Opening Balance")
                              (eq? (length (qif-xtn:splits current-xtn)) 1)
                              (qif-split:category-is-account? 
                               (car (qif-xtn:splits current-xtn))))
                         (begin 
                           (qif-file:set-account! 
                            self (qif-split:category
                                  (car (qif-xtn:splits current-xtn))))
                           (qif-split:set-category! 
                            (car (qif-xtn:splits current-xtn))
                            "Opening Balance")))
                     
                     ;; some special love for stock transactions 
                     (if (and (qif-xtn:security-name current-xtn)
                              (string? (qif-xtn:number current-xtn)))
                         (begin 
                           (cond 
                            ((and 
                              (or (string=? (qif-xtn:number current-xtn)
                                            "ReinvDiv")
                                  (string=? (qif-xtn:number current-xtn)
                                            "ReinvLg")
                                  (string=? (qif-xtn:number current-xtn)
                                            "ReinvSh")
                                  (string=? (qif-xtn:number current-xtn)
                                            "Div"))
                              (string=? 
                               "" (qif-split:category 
                                   (car 
                                    (qif-xtn:splits current-xtn)))))
                             (qif-split:set-category! 
                              (car (qif-xtn:splits current-xtn))
                              "Dividend")
                             ;; KLUDGE! for brokerage accounts 
                             ;; where Dividend pays into the 
                             ;; brokerage account.
                             (if (and (qif-xtn:bank-xtn? current-xtn)
                                      (string? 
                                       (qif-xtn:security-name
                                        current-xtn)))
                                 (qif-xtn:set-payee! 
                                  current-xtn (qif-xtn:security-name
                                               current-xtn))))
                            
                            ((or (string=? (qif-xtn:number current-xtn)
                                           "SellX")
                                 (string=? (qif-xtn:number current-xtn)
                                           "Sell"))
                             (let ((shrs (qif-xtn:num-shares current-xtn)))
                               (cond ((string? shrs)
                                      (qif-xtn:set-num-shares! 
                                       current-xtn
                                       (string-append "-" shrs)))
                                     ((number? shrs)
                                      (qif-xtn:set-num-shares! 
                                       current-xtn (- shrs)))))))))
                     
                     (set! first-xtn #f)                    
                     (set! current-xtn (make-qif-xtn))
                     (set! default-split (make-qif-split)))))
                 
                 
                 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
                 ;; Class transactions 
                 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
                 ((eq? qstate-type 'type:class)
                  (case tag
                    ;; N : name 
                    ((#\N)
                     (qif-class:set-name! current-xtn 
                                          (qif-file:parse-string self value)))
                    
                    ;; D : description 
                    ((#\D)
                     (qif-class:set-description! 
                      current-xtn (qif-file:parse-string self value)))
                    
                    ;; end-of-record
                    ((#\^)
                     (qif-file:add-class! self current-xtn)
                     (set! current-xtn (make-qif-class)))
                    
                    (else
                     (display "qif-file:read-file : unknown Class slot ")
                     (display tag) (newline))))
                 
                 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
                 ;; Account definitions
                 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
                 ((eq? qstate-type 'account)
                  (case tag
                    ((#\N)
                     (qif-acct:set-name! current-xtn 
                                         (qif-file:parse-string self value)))
                    ((#\D)
                     (qif-acct:set-description! 
                      current-xtn (qif-file:parse-string self value)))
                    
                    ((#\T)
                     (qif-acct:set-type! 
                      current-xtn (qif-file:parse-acct-type self value)))
                    
                    ((#\L)
                     (qif-acct:set-limit! 
                      current-xtn (qif-file:parse-value/decimal self value)))
                    
                    ;; B : budget amount.  not really supported. 
                    ((#\B)
                     (qif-acct:set-budget! 
                      current-xtn (qif-file:parse-value/decimal self value)))
                    
                    ((#\^)
                     (if (not ignore-accounts)
                         (set! current-account-name 
                               (qif-acct:name current-xtn)))
                     (qif-file:add-account! self current-xtn)
;;;                    (qif-acct:print current-xtn)
                     (set! current-xtn (make-qif-acct)))))
                 
                 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
                 ;; Category (Cat) transactions 
                 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
                 
                 ((eq? qstate-type 'type:cat)
                  (case tag
                    ;; N : category name 
                    ((#\N)
                     (qif-cat:set-name! current-xtn 
                                        (qif-file:parse-string self value)))
                    
                    ;; D : category description 
                    ((#\D)
                     (qif-cat:set-description! current-xtn 
                                               (qif-file:parse-string 
                                                self value)))
                    
                    ;; E : is this a taxable category?
                    ((#\T)
                     (qif-cat:set-taxable! current-xtn #t))
                    
                    ;; E : is this an expense category?
                    ((#\E)
                     (qif-cat:set-expense-cat! current-xtn #t))
                    
                    ;; I : is this an income category? 
                    ((#\I)
                     (qif-cat:set-income-cat! current-xtn #t))
                    
                    ;; R : what is the tax rate (from some table?
                    ;; seems to be an integer)
                    ((#\R)
                     (qif-cat:set-tax-rate! 
                      current-xtn (qif-file:parse-value/decimal self value)))
                    
                    ;; B : budget amount.  not really supported. 
                    ((#\B)
                     (qif-cat:set-budget-amt! 
                      current-xtn (qif-file:parse-value/decimal self value)))
                    
                    ;; end-of-record
                    ((#\^)
                     (qif-file:add-cat! self current-xtn)
;;;                    (qif-cat:print current-xtn)
                     (set! current-xtn (make-qif-cat)))
                    
                    (else
                     (display "qif-file:read-file : unknown Cat slot ")
                     (display tag) (newline))))
                 
                 ;; trying to sneak one by, eh? 
                 (#t 
                  (if (not qstate-type)
                      (begin
                        (display "line = ") (display line) (newline)
                        (display "qif-file:read-file : ")
                        (display "file does not appear to be a QIF file.")
                        (newline)
                        (set! heinous-error #t)))))
                
                ;; this is if we read a normal (non-null, non-eof) line...
                (if (not heinous-error)
                    (line-loop)))
              
              ;; and this is if we read a null or eof line 
              (if (and (not heinous-error)
                       (not (eof-object? line)))
                  (line-loop))))))
    
    (if (not heinous-error)
        (begin 
          ;; now that the file is read in, figure out if either 
          ;; the date or radix format has made itself clear from the 
          ;; values. 
          (if (and 
               (eq? (qif-file:radix-format self) 'unknown)
               (not (eq? (qif-file:guessed-radix-format self) 'unknown))
               (not (eq? (qif-file:guessed-radix-format self) 'inconsistent)))
              (qif-file:set-radix-format! 
               self 
               (qif-file:guessed-radix-format self)))
          
          (if (and 
               (eq? (qif-file:date-format self) 'unknown)
               (not (eq? (qif-file:guessed-date-format self) 'unknown))
               (not (eq? (qif-file:guessed-date-format self) 'inconsistent)))
              (qif-file:set-date-format! self 
                                         (qif-file:guessed-date-format self)))
          
          ;; if the account hasn't been found from an Opening Balance line,
          ;; just set it to the filename and force the user to specify it.
          (if (eq? 'unknown (qif-file:account self))
              (qif-file:set-account! 
               self (qif-file:path-to-accountname self)))
          
          ;; reparse values and dates if we figured out the format.
          (let ((reparse-ok #t))
            (for-each 
             (lambda (xtn)
               (if (eq? reparse-ok #t)
                   (set! reparse-ok 
                         (qif-xtn:reparse xtn self))))
             (qif-file:xtns self))
            
            (for-each
             (lambda (cat)
               (if (eq? reparse-ok #t)
                   (set! reparse-ok 
                         (qif-cat:reparse cat self))))
             (qif-file:cats self))
            
            (for-each
             (lambda (acct)
               (if (eq? reparse-ok #t)
                   (set! reparse-ok 
                         (qif-acct:reparse acct self))))
             (qif-file:accounts self))
            reparse-ok))
        (begin 
          (display "There was a heinous error.  Failed to read file.")
          (newline)
          #f))))

