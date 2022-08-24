;;; reverso.el --- Translation, grammar checking and bilingual concordances -*- lexical-binding: t -*-

;; Copyright (C) 2022 Korytov Pavel

;; Author: Korytov Pavel <thexcloud@gmail.com>
;; Maintainer: Korytov Pavel <thexcloud@gmail.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (transient "0.3.7") (request "0.3.2"))
;; Homepage: https://github.com/SqrtMinusOne/reverso.el

;; This file is NOT part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; TODO

;;; Code:
(require 'request)
(require 'transient)
(require 'url-util)
(require 'dom)

(declare-function evil-define-key* "evil-core")

(defgroup reverso nil
  "Translation, grammar checking and bilingual concordances."
  :group 'applications)

(defface reverso-highlight-face
  '((t (:inherit underline)))
  "Face for highlighting selected words in translation."
  :group 'reverso)

(defface reverso-error-face
  '((t (:inherit error)))
  "Face for highlighting errors in grammar check."
  :group 'reverso)

(defface reverso-heading-face
  '((t (:inherit transient-heading)))
  "Face for headings in reverso buffers."
  :group 'reverso)

(defface reverso-keyword-face
  '((t (:inherit transient-value)))
  "Face for various keywords in reverso buffers."
  :group 'reverso)

(defface reverso-definition-face
  '((t (:inherit italic)))
  "Face for word definitions in reverso buffer."
  :group 'reverso)

(defcustom reverso-max-display-lines-in-input 5
  "Maximum number of lines to display in input."
  :type 'integer
  :group 'reverso)

(defcustom reverso-language-completing-read-threshold 4
  "Minimum number of languages to choose with `completing-read'."
  :type 'integer
  :group 'reverso)

(defconst reverso--language-mapping
  '((english . eng)
    (german . ger)
    (spanish . spa)
    (arabic . ara)
    (french . fra)
    (hebrew . heb)
    (italian . ita)
    (japanese . jpn)
    (dutch . dut)
    (polish . pol)
    (portuguese . por)
    (romanian . rum)
    (russian . rus)
    (ukrainian . ukr)
    (turkish . tur)
    (chinese . chi)
    (swedish . swe))
  "Mapping from long language names to short ones.

This one is used for the translation queries.")

(defconst reverso--language-mapping-1
  '((english . en)
    (german . de)
    (arabic . ar)
    (french . fr)
    (spanish . es)
    (french . fr)
    (hebrew . he)
    (italian . it)
    (japanese . ja)
    (dutch . nl)
    (polish . pl)
    (portuguese . pt)
    (romanian . ro)
    (russian . ru))
  "Another mapping from long language names to short ones.

This one is used for the synonym queries.")

(defconst reverso--right-to-left-languages
  '(arabic hebrew)
  "List of languages that are written from right to left.")

(defcustom reverso-languages (mapcar #'car reverso--language-mapping)
  "Subset of languages to use."
  :type `(set ,@(cl-loop for cell in reverso--language-mapping
                         collect (list 'const (car cell)))))

(defconst reverso--languages
  '((translation . (arabic german english spanish french hebrew italian
                           japanese dutch polish portuguese romanian russian
                           swedish turkish ukrainian chinese))
    (context . (arabic german english spanish french hebrew italian
                       japanese dutch polish portuguese romanian
                       russian swedish turkish ukrainian chinese))
    (grammar . (english french))
    (synonyms . (arabic german english spanish french hebrew italian
                        japanese dutch polish portuguese romanian
                        russian)))
  "Available languages for diferent operations.")

(defconst reverso--languages-compatible
  `((context
     . ((arabic . (english german spanish french hebrew italian
                           portuguese russian turkish ukrainian))
        (german . (arabic english spanish french hebrew italian
                          japanese dutch polish portuguese romanian
                          russian swedish turkish ukrainian))
        (english . (arabic german spanish french hebrew italian
                           japanese dutch polish portuguese romanian
                           russian swedish turkish ukraninan chinese))
        (spanish . (arabic german english french hebrew italian
                           japanese dutch polish portuguese romanian
                           russian swedish turkish chinese ukrainian))
        (french . (arabic german spanish english hebrew italian
                          japanese dutch polish portuguese romanian
                          russian swedish turkish chinese ukrainian))
        (hebrew . (arabic german english spanish french italian dutch
                          portuguese russian ukrainian))
        (italian . (arabic german english spanish french hebrew
                           japanese dutch polish portuguese romanian
                           russian swedish turkish ukrainian))
        (japanese . (german english spanish french italian portuguese
                            russian ukrainian))
        (dutch . (german english spanish french hebrew italian
                         portuguese russian ukrainian))
        (polish . (german english spanish french italian ukrainian))
        (portuguese . (arabic german english spanish french hebrew italian
                              japanese dutch russian turkish ukrainian))
        (romanian . (german english spanish french italian turkish ukrainian))
        (russian . (arabic german english spanish french hebrew italian
                           japanese dutch portuguese ukrainian))
        (swedish . (german english spanish french italian ukrainian))
        (turkish . (arabic german english spanish french italian
                           portuguese romanian ukrainian))
        (ukrainian . (english))
        (chinese . (english french spanish ukrainian))))
    (translation
     . ((arabic . (german english spanish french hebrew italian
                          portuguese russian turkish))
        (german . (arabic english spanish french hebrew italian
                          japanese dutch polish portuguese romanian
                          russian swedish turkish ukrainian))
        (english . (arabic german spanish french hebrew italian
                           japanese dutch polish portuguese romanian
                           russian swedish turkish ukrainian chinese))
        (spanish . (arabic german english french hebrew italian
                           japanese dutch polish portuguese romanian
                           russian swedish turkish chinese ukrainian))
        (french . (arabic german english spanish hebrew italian
                          japanese dutch polish portuguese romanian
                          russian swedish turkish chinese ukrainian))
        (hebrew . (arabic german english spanish french italian dutch
                          portuguese russian ukrainian))
        (italian . (arabic german english spanish french hebrew
                           japanese dutch polish portuguese romanian
                           russian swedish turkish ukrainian))
        (japanese . (german english spanish french italian portuguese
                            russian ukrainian))
        (dutch . (german english spanish french hebrew italian
                         portuguese russian ukrainian))
        (polish . (german english spanish french italian ukrainian))
        (portuguese . (arabic german english spanish french hebrew
                              italian japanese dutch russian turkish
                              ukrainian))
        (romanian . (german english spanish french italian turkish
                            ukrainian))
        (russian . (arabic german english spanish french hebrew italian
                           japanese dutch portuguese ukrainian))
        (swedish . (german english spanish french italian ukrainian))
        (turkish . (arabic german english spanish french italian
                           portuguese romanian ukrainian))
        (ukrainian . (english))
        (chinese . (english french spanish ukrainian)))))
  "Compatibility of languages for different operations.")

(defun reverso-verify-settings ()
  "Check if the settings are correct."
  (interactive)
  (let ((languages (mapcar #'car reverso--language-mapping)))
    (dolist (cell reverso--languages)
      (dolist (lang (cdr cell))
        (unless (memq lang languages)
          (error "Language %s is not available (reverso--languages)" lang))))
    (dolist (lang reverso-languages)
      (unless (memq lang languages)
        (error "Language %s is not available (reverso-languages)" lang)))
    (dolist (cell-kind reverso--languages-compatible)
      (dolist (cell-lang (cdr cell-kind))
        (unless (memq (car cell-lang) languages)
          (error
           "Language %s is not available (reverso--languages-compatible)"
           (car cell-lang)))
        (dolist (lang (cdr cell-lang))
          (unless (memq lang languages)
            (error
             "Language %s is not available (reverso--languages-compatible)"
             lang))))))
  (message "Everything is OK"))

;;; API

(defconst reverso--urls
  '((translation . "https://api.reverso.net/translate/v1/translation")
    (context . "https://context.reverso.net/translation/")
    (grammar . "https://orthographe.reverso.net/api/v1/Spelling")
    (synomyms . "https://synonyms.reverso.net/synonym/"))
  "URLs with reverso endpoints.")

(defconst reverso--user-agents
  '("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/104.0.0.0 Safari/537.36"
                          "Mozilla/5.0 (X11; Linux x86_64; rv:103.0) Gecko/20100101 Firefox/103.0"
                          "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:103.0) Gecko/20100101 Firefox/103.0"
                          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/104.0.0.0 Safari/537.36"
                          "Mozilla/5.0 (Windows NT 10.0; rv:103.0) Gecko/20100101 Firefox/103.0"
                          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/103.0.0.0 Safari/537.36"
                          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.6 Safari/605.1.15"
                          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:103.0) Gecko/20100101 Firefox/103.0")
  "User-Agents to use for reverso.el requests.

A random one is be picked at package initialization.")

(defvar reverso--user-agent
  (nth (random (length reverso--user-agents))
       reverso--user-agents)
  "User-Agent to use for reverso.el requests.")

(defun reverso--translate (text source target cb)
  "Translate TEXT from language SOURCE to TARGET.

SOURCE and TARGET are keys of `reverso--languages'.  CB is called with
the result.

The result is an alist with the following keys:
- `:corrected-text': corrected version of SOURCE (if available)
- `:language-from': the source language
- `:language-to': the target language
- `:detected-language': the detected source language
- `:translation': a string with translated text
- `:context-results': a list with found contexts.
   An item of the list is an alist with the keys:
   - `:source': a string in the source language
   - `:target': a string in the target language"
  (when (string-empty-p text)
    (user-error "Empty input!"))
  (unless (and (alist-get source reverso--language-mapping)
               (member source
                       (alist-get 'translation reverso--languages)))
    (error "Wrong language: %s" source))
  (unless (and (alist-get target reverso--language-mapping)
               (member source
                       (alist-get 'translation reverso--languages)))
    (error "Wrong language: %s" target))
  (unless (member target
                  (alist-get source
                             (alist-get 'translation reverso--languages-compatible)))
    (error "Language %s is not compatible with %s" target source))
  (request (alist-get 'translation reverso--urls)
    :type "POST"
    :data (json-encode
           `((format . "text")
             (from . ,(alist-get source reverso--language-mapping))
             (input . ,text)
             (options . ((contextResults . t)
                         (languageDetection . t)
                         (origin . "reversomobile")
                         (sentenceSpliiter . :json-false)))
             (to . ,(alist-get target reverso--language-mapping))))
    :headers `(("Content-Type" . "application/json")
               ("Accept" . "*/*")
               ("Connection" . "keep-alive")
               ("User-Agent" . ,reverso--user-agent))
    :parser 'json-read
    :encoding 'utf-8
    :success (cl-function
              (lambda (&key data &allow-other-keys)
                (funcall cb (reverso--alist-remove-empty-values
                             (reverso--translate-parse data)))))
    :error (cl-function
            (lambda (&key error-thrown &allow-other-keys)
              (message "Error!: %S" error-thrown)))))

(defun reverso--convert-string (dom)
  "Convert DOM from the reverso API to fontified string.

reverso.net uses tags to highlight relevant works, e.g. <em> for the
selected word in the context search.  This function fontifies words
that are in tags with `reverso-highlight-face'"
  (thread-last
    (mapconcat (lambda (node)
                 (let ((text (if (listp node) (dom-texts node) node))
                       (is-special (listp node)))
                   (if is-special
                       (propertize text 'face 'reverso-highlight-face)
                     text)))
               (dom-children dom)
               "")
    (string-trim)
    (replace-regexp-in-string
     (rx (+ (syntax whitespace))",") ",")
    (replace-regexp-in-string
     (rx (+ (syntax whitespace))) " ")))

(defun reverso--convert-string-html (html)
  "Convert HTML string from the reverso API to fontified string."
  (with-temp-buffer
    (insert "<html><body>" html "<body></html>")
    (reverso--convert-string
     (car
      (dom-by-tag
       (libxml-parse-html-region (point-min) (point-max))
       'body)))))

(defun reverso--alist-remove-empty-values (alist)
  "Remove empty values from ALIST."
  (cl-loop for (key . value) in alist
           if value
           collect (cons key value)))

(defun reverso--alist-get-inv (alist lookup-value)
  "Like `alist-get', but with `car' and `cdr' swapped.

ALIST is an alist, LOOKUP-VALUE is a value to look in `cdr'."
  (cl-loop for (key . value) in alist
           if (equal lookup-value value)
           return key))

(defun reverso--translate-parse (response)
  "Convert RESPONSE from the reverso translation API into an alist."
  (let ((corrected-text (alist-get 'correctedText response))
        (language-from (reverso--alist-get-inv
                        reverso--language-mapping
                        (intern (alist-get 'from response))))
        (language-to (reverso--alist-get-inv
                      reverso--language-mapping
                      (intern (alist-get 'to response))))
        (detected-language (reverso--alist-get-inv
                            reverso--language-mapping
                            (intern (or
                                     (alist-get 'detectedLanguage
                                                (alist-get 'languageDetection response))
                                     "nil"))))
        (translation (seq-elt (alist-get 'translation response) 0))
        (context-results
         (cl-loop for r across (alist-get 'results (alist-get 'contextResults response))
                  collect
                  `((:translation . ,(alist-get 'translation r))
                    (:context
                     . ,(cl-loop for source across (alist-get 'sourceExamples r)
                                 for target across (alist-get 'targetExamples r)
                                 collect
                                 `((:source . ,(reverso--convert-string-html source))
                                   (:target . ,(reverso--convert-string-html target)))))))))
    `((:corrected-text . ,corrected-text)
      (:language-from . ,language-from)
      (:language-to . ,language-to)
      (:detected-language . ,detected-language)
      (:translation . ,translation)
      (:context-results . ,context-results))))

(defun reverso--get-context (text source target cb)
  "Find bilingual concordances for TEXT.

SOURCE and TARGET are keys of `reverso--languages'.  CB is called with
the result.

The result is a list of alists with the keys:
- `:source': a string in the source language
- `:target': the same string in the target language"
  (unless (and (alist-get source reverso--language-mapping)
               (member source
                       (alist-get 'context reverso--languages)))
    (error "Wrong language: %s" source))
  (unless (and (alist-get target reverso--language-mapping)
               (member source
                       (alist-get 'context reverso--languages)))
    (error "Wrong language: %s" target))
  (unless (member target
                  (alist-get source
                             (alist-get 'context reverso--languages-compatible)))
    (error "Language %s is not compatible with %s" target source))
  (request (concat (alist-get 'context reverso--urls)
                   (symbol-name source) "-" (symbol-name target) "/"
                   (replace-regexp-in-string
                    "%20" "+" (url-hexify-string text) t t))
    :type "GET"
    :headers `(("Accept" . "*/*")
               ("Connection" . "keep-alive")
               ("User-Agent" . ,reverso--user-agent))
    :parser 'buffer-string
    :encoding 'utf-8
    :success (cl-function
              (lambda (&key data &allow-other-keys)
                (funcall cb (reverso--alist-remove-empty-values
                             (reverso--get-context-parse data)))))
    :error (cl-function
            (lambda (&key error-thrown &allow-other-keys)
              (message "Error!: %S" error-thrown)))))

(defun reverso--get-context-parse (data)
  "Parse response from reverso context API.

DATA is an html string."
  (let ((html (with-temp-buffer
                (insert data)
                (libxml-parse-html-region (point-min) (point-max)))))
    (let ((examples (dom-by-id html "examples-content")))
      (cl-loop for child in (dom-non-text-children examples)
               for classes = (alist-get 'class (dom-attributes child))
               when (string-match-p (rx "example") classes)
               collect (let ((src (dom-by-class (dom-by-class child "src") "text"))
                             (trg (dom-by-class (dom-by-class child "trg") "text")))
                         `((:source . ,(reverso--convert-string src))
                           (:target . ,(reverso--convert-string trg))))))))

(defun reverso--get-synomyms (text language cb)
  "Get synomyms for TEXT in LANGUAGE.

CB is called with the result.

The result is a list of alists with the following keys:
- `:kind': part of speech
- `:synonyms': list of alists:
   - `:synonym': word
   - `:relevant': if t, considered a \"good match\" by the service
- `:examples': list of strings with examples
- `:antonyms': list of alists
   - `:antonym': word"
  (unless (alist-get language reverso--language-mapping-1)
    (error "Wrong language: %s" language))
  (request (concat (alist-get 'synomyms reverso--urls)
                   (symbol-name (alist-get language reverso--language-mapping-1)) "/"
                   (url-hexify-string text))
    :type "GET"
    :headers `(("Accept" . "*/*")
               ("Connection" . "keep-alive")
               ("User-Agent" . ,reverso--user-agent))
    :parser 'buffer-string
    :encoding 'utf-8
    :success (cl-function
              (lambda (&key data &allow-other-keys)
                (funcall cb (reverso--alist-remove-empty-values
                             (reverso--get-synomyms-parse data)))))
    :error (cl-function
            (lambda (&key error-thrown &allow-other-keys)
              (message "Error!: %S" error-thrown)))))

(defun reverso--get-synomyms-parse (html)
  "Parse the reverso synomyms page.

HTML is a string."
  (let* ((dom (with-temp-buffer
                (insert html)
                (libxml-parse-html-region (point-min) (point-max)))))
    (cl-loop
     for child in (dom-non-text-children
                   (dom-by-id (dom-by-tag dom 'body) "synonyms"))
     if (string-match-p "wrap-hold-prop" (or (dom-attr child 'class) ""))
     collect
     `((:kind . ,(string-trim (dom-texts (dom-by-class child "words-options"))))
       (:synonyms
        . ,(cl-loop
            for synonym in (dom-non-text-children
                            (dom-by-class (car (dom-by-class child "word-opt"))
                                          "word-box"))
            for a = (car (dom-by-tag synonym 'a))
            collect
            `((:synonym . ,(string-trim (dom-texts synonym)))
              (:relevant
               . ,(and (string-match-p "relevant" (or (dom-attr a 'class) "")) t)))))
       (:examples
        . ,(cl-loop
            for example in (dom-non-text-children
                            (dom-by-class child "phrases-examples"))
            for span = (car (dom-by-tag example 'span))
            if span
            collect (reverso--convert-string span)))
       (:antonyms
        . ,(cl-loop
            for antonym in (dom-non-text-children
                            (dom-by-class (car (dom-by-class child "antonyms-wrapper"))
                                          "word-box"))
            for a = (car (dom-by-tag antonym 'a))
            for text = (string-trim (dom-texts antonym))
            unless (string-match-p (rx "...") text)
            collect
            `((:antonym . ,text))))))))

(defun reverso--get-grammar (text language cb)
  "Check TEXT in LANGUAGE for errors.

CB is called with the result.

The result is an alist with the keys:
`:corrected-text': corrected version of TEXT
`:source-text-hl': TEXT with highlighted errors
`:corrections': a list of alists with keys:
  - `:type': error type
  - `:short-description'
  - `:long-description'
  - `:mistake-text': part of TEXT with the error
  - `:correction-text': corrected version of `:mistake-text'
  - `:correction-defition': definiton of `:correction-text', if
    available
  - `:start-index': start index in TEXT
  - `:end-index': end index TEXT
  - `:suggestions': a list of alists with keys:
    - `:text': the suggested text
    - `:definition': definition of `:text', if available
    - `:category': category of the correction, if available"
  (unless (member language (alist-get 'grammar reverso--languages))
    (error "Wrong language: %s" language))
  (request (concat (alist-get 'grammar reverso--urls)
                   "?text=" (url-hexify-string text)
                   "&language=" (symbol-name
                                 (alist-get language reverso--language-mapping))
                   "&getCorrectionDetails=true")
    :type "GET"
    :headers `(("Accept" . "*/*")
               ("Connection" . "keep-alive")
               ("User-Agent" . ,reverso--user-agent))
    :parser 'json-read
    :encoding 'utf-8
    :success (cl-function
              (lambda (&key data &allow-other-keys)
                (funcall cb (reverso--alist-remove-empty-values
                             (reverso--get-grammar-parse text data)))))
    :error (cl-function
            (lambda (&key error-thrown &allow-other-keys)
              (message "Error!: %S" error-thrown)))))

(defun reverso--get-grammar-parse (source-text data)
  "Parse the reverso grammar API response.

SOURCE-TEXT is the text sent for checking.  DATA is the JSON reply."
  (let* ((corrected-text (alist-get 'text data))
         (source-text-hl
          (with-temp-buffer
            (insert source-text)
            (cl-loop for corr across (alist-get 'corrections data)
                     if (alist-get 'startIndex corr)
                     do (put-text-property (1+ (alist-get 'startIndex corr))
                                           (+ 2 (alist-get 'endIndex corr))
                                           'face 'reverso-error-face))
            (buffer-string)))
         (corrections
          (cl-loop
           for corr across (alist-get 'corrections data)
           collect `((:type . ,(alist-get 'type corr))
                     (:short-description . ,(alist-get 'shortDescription corr))
                     (:long-description . ,(alist-get 'longDescription corr))
                     (:mistake-text . ,(alist-get 'mistakeText corr))
                     (:correction-text . ,(alist-get 'correctionText corr))
                     (:correction-defition . ,(alist-get 'correctionDefinition corr))
                     (:start-index . ,(alist-get 'startIndex corr))
                     (:end-index . ,(alist-get 'endIndex corr))
                     (:suggestions
                      . ,(cl-loop for s across (alist-get 'suggestions corr)
                                  collect
                                  `((:text . ,(alist-get 'text s))
                                    (:definition . ,(alist-get 'definition s))
                                    (:category . ,(alist-get 'category s)))))))))
    `((:corrected-text . ,corrected-text)
      (:source-text-hl . ,source-text-hl)
      (:corrections . ,corrections))))

;;; Buffers

(defvar reverso-result-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") (lambda ()
                                (interactive)
                                (quit-window t)))
    (when (fboundp #'evil-define-key*)
      (evil-define-key* '(normal motion) map
        "q" (lambda ()
              (interactive)
              (quit-window t))))
    map)
  "Keymap used in `reverso-result-mode' buffers.")

(defvar-local reverso--input nil
  "Displayed input for `reverso'.")

(defvar-local reverso--output nil
  "Displayed output for `reverso'.")

(defvar-local reverso--data nil
  "Received data for `reverso'.")

(define-derived-mode reverso-result-mode special-mode "Reverso results"
  "Major mode to display results of `reverso'."
  :group 'reverso)

(defun reverso--translate-render (text data)
  "Render the translation results.

DATA is an alist as defined in `reverso--translate'.  TEXT is the
source text."
  (let ((multiline (string-match-p "\n" text)))
    (insert (propertize
             (symbol-name (alist-get :language-from data))
             'face 'reverso-keyword-face)
            " -> "
            (propertize
             (symbol-name (alist-get :language-to data))
             'face 'reverso-keyword-face))
    (when (alist-get :detected-language data)
      (insert " [detected: "
              (propertize
               (symbol-name (alist-get :detected-language data))
               'face 'reverso-keyword-face)
              "]"))
    (insert "\n\n")

    (insert (propertize
             "Source text: "
             'face 'reverso-heading-face))
    (when multiline
      (insert "\n")
      (when (memq (alist-get :language-from data)
                  reverso--right-to-left-languages)
        (insert "\n")))
    (insert text "\n\n")
    (setq-local reverso--input text)

    (when (alist-get :corrected-text data)
      (insert (propertize
               "Corrected text: "
               'face 'reverso-heading-face))
      (when (memq (alist-get :language-from data)
                  reverso--right-to-left-languages)
        (insert "\n"))
      (insert (alist-get :corrected-text data) "\n\n"))

    (if (alist-get :translation data)
        (progn
          (setq-local reverso--output (alist-get :translation data))
          (insert
           (propertize
            "Translation: "
            'face 'reverso-heading-face))
          (when multiline
            (insert "\n")
            (when (memq (alist-get :language-to data)
                        reverso--right-to-left-languages)
              (insert "\n")))
          (insert (alist-get :translation data) "\n\n"))
      (insert "No results!"))
    (when (alist-get :context-results data)
      (insert (propertize
               "Context results: "
               'face 'reverso-heading-face)
              "\n")
      (cl-loop for result in (alist-get :context-results data)
               for translation = (alist-get :translation result)
               when (not (string-empty-p translation))
               do (insert
                   (propertize
                    translation
                    'face 'reverso-highlight-face)
                   "\n")
               do (reverso--context-render-list
                   (alist-get :context result)
                   (alist-get :language-to data)
                   (or (alist-get :detected-language data)
                       (alist-get :language-from data)))))))

(defun reverso--context-render-list (data lang-to lang-from)
  "Render a list of context translation results.

DATA is a list of alists with the following keys:
- `:source': string in the source language (LANG-FROM)
- `:target': string in the target language (LANG-TO)"
  (cl-loop with lang-to-name = (symbol-name lang-to)
           with lang-from-name = (symbol-name lang-from)
           with lang-length = (max (length lang-to-name) (length lang-from-name))
           for datum in data
           for source = (alist-get :source datum)
           for target = (alist-get :target datum)
           do (insert (propertize
                       (format (format "%%-%ds: " lang-length) lang-to-name)
                       'face 'reverso-keyword-face)
                      source "\n"
                      (propertize
                       (format (format "%%%ds: " lang-length) lang-from-name)
                       'face 'reverso-keyword-face)
                      target "\n\n")))

(defun reverso--translate-render-brief (text data)
  "Render the translation results in brief format.

DATA is an alist as defined in `reverso--translate'.  TEXT is the
source text."
  (setq-local reverso--input text)
  (if (alist-get :translation data)
      (progn
        (setq-local reverso--output (alist-get :translation data))
        (insert (alist-get :translation data)))
    (insert "No results!")))

(defun reverso--context-render (input data lang-to lang-from)
  "Render context translation results.

INPUT is the input string.  DATA is a list as defined in
`reverso--get-context'.  LANG-TO and LANG-FROM and the target and
source languages."
  (setq-local reverso--input input)
  (insert (propertize
           "Context results: "
           'face 'reverso-heading-face)
          "\n")
  (reverso--context-render-list data lang-to lang-from))

(defun reverso--synonyms-render (input data)
  "Render synonym search results.

INPUT is the input string.  DATA is a list as defined in
`reverso--get-synomyms'."
  (setq-local reverso--input input)
  (setq my/test data)
  (dolist (datum data)
    (when (alist-get :kind datum)
      (insert (propertize
               "Part of speech: "
               'face 'reverso-keyword-face)
              (alist-get :kind datum)
              "\n"))
    (when (alist-get :synonyms datum)
      (insert (propertize
               "Synomyms: "
               'face 'reverso-heading-face)
              "\n")
      (dolist (synonym (alist-get :synonyms datum))
        (when (alist-get :relevant synonym)
          (insert "- " (alist-get :synonym synonym) "\n")))
      (insert "\n"))
    (when (alist-get :examples datum)
      (insert (propertize
               "Examples: "
               'face 'reverso-heading-face)
              "\n")
      (dolist (example (alist-get :examples datum))
        (insert example "\n"))
      (insert "\n"))
    (when (alist-get :antonyms datum)
      (insert (propertize
               "Antonyms: "
               'face 'reverso-heading-face)
              "\n")
      (dolist (antonym (alist-get :antonyms datum))
        (insert "- " (alist-get :antonym antonym) "\n"))
      (insert "\n"))))

(defun reverso--grammar-render (data)
  "Render grammar checking results.

DATA is an alist as defined in `reverso--get-grammar'."
  (insert
   (propertize "Source text: " 'face 'reverso-heading-face)
   "\n"
   (alist-get :source-text-hl data)
   "\n\n"
   (propertize "Corrected text: " 'face 'reverso-heading-face)
   "\n"
   (alist-get :corrected-text data)
   "\n\n")
  (when (alist-get :corrections data)
    (insert
     (propertize "Corrections: " 'face 'reverso-heading-face)
     "\n")
    (dolist (corr (alist-get :corrections data))
      (insert
       (propertize (or (alist-get :type corr) "")
                   'face 'reverso-keyword-face))
      (when (alist-get :short-description corr)
        (insert ": " (alist-get :short-description corr)))
      (insert "\n")
      (when (alist-get :long-description corr)
        (insert (alist-get :long-description corr))
        (insert "\n"))
      (insert "\n")
      (insert
       (propertize
        (or (alist-get :mistake-text corr) "")
        'face 'reverso-highlight-face)
       " -> "
       (propertize
        (or (alist-get :correction-text corr) "")
        'face 'reverso-highlight-face))
      (when (alist-get :correction-defition corr)
        (insert " [" (propertize
                      (alist-get :correction-defition corr)
                      'face 'reverso-definition-face)
                "]"))
      (insert "\n\n")
      (when (alist-get :suggestions corr)
        (insert "Suggestions:\n")
        (dolist (sg (alist-get :suggestions corr))
          (insert "- ")
          (when (alist-get :category sg)
            (insert (alist-get :category sg) ": "))
          (insert (propertize
                   (alist-get :text sg)
                   'face 'reverso-highlight-face))
          (when (alist-get :definition sg)
            (insert
             " ["
             (propertize
              (alist-get :definition sg)
              'face 'reverso-definition-face)
             "]"))
          (insert "\n"))
        (insert "\n")))))

(defmacro reverso--with-buffer (&rest body)
  "Execute BODY in the clean `reverso' results buffer."
  (declare (indent 0))
  `(progn
     (let ((buffer (get-buffer-create
                    (generate-new-buffer-name "*Reverso*"))))
       (with-current-buffer buffer
         (unless (derived-mode-p 'reverso-result-mode)
           (reverso-result-mode))
         (let ((inhibit-read-only t))
           (erase-buffer)
           ,@body)
         (goto-char (point-min)))
       (switch-to-buffer-other-window buffer))))

;;; Transient

(defclass reverso--transient-input (transient-infix)
  ((format :initform " %k %d: %v"))
  "Class used for retrieving the input string.")

(defvar reverso--use-buffer-as-input nil
  "Whether to use the current buffer as input.

That parameter is normally set by the prefix argument, but as it
doesn't pesist between parent and child invocations, this variable is
used instead.")

(cl-defmethod transient-init-value ((obj reverso--transient-input))
  "Initialize the value of `reverso--transient-input'.

OBJ is an instance of the class."
  (oset obj value
        (cond
         ((and (slot-boundp obj 'value) (oref obj value))
          (oref obj value))
         ((region-active-p)
          (buffer-substring-no-properties (region-beginning) (region-end)))
         ((or (equal current-prefix-arg '(4))
              reverso--use-buffer-as-input)
          (if reverso--output
              reverso--output
            (buffer-substring-no-properties (point-min) (point-max))))
         (reverso--input reverso--input)
         (t ""))))

(cl-defmethod transient-infix-read ((obj reverso--transient-input))
  "Read input string from the minibuffer.

OBJ is an instance of the `reverso--transient-input'."
  (read-from-minibuffer "Input: " (oref obj value)))

(cl-defmethod transient-format-value ((obj reverso--transient-input))
  "Format the input string for display in the transient buffer.

OBJ is an instance of `reverso--transient-input'."
  (propertize
   (with-temp-buffer
     (insert (oref obj value))
     (goto-char (point-min))
     (let ((lines (count-lines (point-min) (point-max))))
       (cond
        ((= (buffer-size) 0) "(empty)")
        ((= lines 1) (buffer-string))
        ((> lines reverso-max-display-lines-in-input)
         (concat
          "\n"
          (buffer-substring
           (point-min)
           (save-excursion
             (goto-char (point-min))
             (forward-line (1- reverso-max-display-lines-in-input))
             (point)))
          "\n... (truncated "
          (number-to-string
           (- lines reverso-max-display-lines-in-input))
          " more lines)"))
        (t (concat "\n" (buffer-string))))))
   'face 'transient-value))

(defclass reverso--transient-language (transient-infix)
  ((format :initform " %k %d %v")
   (languages :initarg :languages :initform nil)
   (target-languages :initarg :target-languages :initform nil)
   (is-target :initarg :is-target :initform nil))
  "Class used for switching the language.")

(defvar reverso--source-value nil
  "Selected source language in `reverso'.

Used for persistence between invocations of transient buffers.")

(defvar reverso--target-value nil
  "Selected target language in `reverso'.

Used for persistence between invocations of transient buffers.")

(defvar reverso--prefer-brief nil
  "If non-nil, select brief translation display by default.

Used for persistence between invocations of transient buffers.")

(defun reverso--get-available-languages (obj)
  "Get available languages for the operation.

OBJ is an instance of transient infix.  It needs to have the following
slots:
- `languages': list of available languages
- `is-target': if OBJ selects a target language
- `target-languages': alist, where the key is a source language, and
  the value is a list of available target languages for that source
  language.

If `is-target' is non-nil, then selection of languages has to limited.
In that case, `reverso--source-value' is used to get the source
language."
  (let* ((all-languages
          (seq-sort
           (lambda (a b) (string-lessp (symbol-name a)
                                       (symbol-name b)))
           (or (oref obj languages)
               (mapcar #'car reverso--language-mapping))))
         (is-target (oref obj is-target))
         (source-language (when is-target
                            (or reverso--source-value
                                (car all-languages))))
         (target-languages (when (and is-target (oref obj target-languages))
                             (alist-get source-language (oref obj target-languages))))
         (languages (cl-loop for lang in all-languages
                             if (or (not source-language)
                                    (not (eq source-language lang)))
                             collect lang)))
    (seq-sort
     (lambda (a b) (string-lessp (symbol-name a)
                                 (symbol-name b)))
     (let ((intersection-1 (seq-intersection languages reverso-languages)))
       (if (not target-languages)
           intersection-1
         (seq-intersection intersection-1 target-languages))))))

(defun reverso--get-language-variable (obj)
  "Get the name of the variable that stores the selected language.

OBJ is an instance of a transient infix, that has to have a slot
called `is-target'."
  (if (oref obj is-target)
      'reverso--target-value
    'reverso--source-value))

(cl-defmethod transient-init-value ((obj reverso--transient-language))
  "Initialize the value for the language picker.

OBJ is an instance of `reverso--transient-language'."
  (let ((value
         (cond
          ((and (slot-boundp obj 'value) (oref obj value))
           (oref obj value))
          ((and (symbol-value (reverso--get-language-variable obj)))
           (symbol-value (reverso--get-language-variable obj)))
          (t (car (reverso--get-available-languages
                   obj
                   (oref obj target-languages)
                   (oref obj is-target)))))))
    (set (reverso--get-language-variable obj) value)
    (oset obj value value)))

(cl-defmethod transient-format-value ((obj reverso--transient-language))
  "Format the value of the language picker.

OBJ is an instance of `reverso--transient-language'."
  (let ((value (transient-infix-value obj)))
    (concat
     (propertize "[" 'face 'transient-inactive-value)
     (mapconcat
      (lambda (choice)
        (propertize (symbol-name choice) 'face
                    (if (eq choice value)
                        'transient-value
                      'transient-inactive-value)))
      (reverso--get-available-languages obj)
      (propertize "|" 'face 'transient-inactive-value))
     (propertize "]" 'face 'transient-inactive-value))))

(cl-defmethod transient-infix-read ((obj reverso--transient-language))
  "Pick a value in the language picker.

OBJ is an instance of `reverso--transient-language'."
  (let* ((choices (reverso--get-available-languages obj))
         (current-idx (or (cl-position (oref obj value) choices) -1))
         (next-idx (% (1+ current-idx) (length choices)))
         (next-choice
          (if (> (length choices) reverso-language-completing-read-threshold)
              (let ((lang (intern
                           (completing-read
                            "Language: "
                            (mapcar #'symbol-name choices) nil t))))
                (unless (member lang choices)
                  (user-error "Bad language: %s" lang))
                lang)
            (nth next-idx choices))))
    (set (reverso--get-language-variable obj) next-choice)
    next-choice))

(cl-defmethod transient-infix-value ((obj reverso--transient-language))
  "Get the current value of the language picker.

OBJ is an instance of `reverso--transient-language'."
  (let* ((choices (reverso--get-available-languages obj))
         (current-idx (or (cl-position (oref obj value) choices) -1)))
    (nth current-idx choices)))

(defclass reverso--transient-brief (transient-switch) ()
  "Toggle brief output.")

(cl-defmethod transient-init-value ((obj reverso--transient-brief))
  "Initialize the value of the brief output switcher.

OBJ is an instance of `reverso--transient-brief'."
  (oset obj value reverso--prefer-brief))

(cl-defmethod transient-infix-read ((obj reverso--transient-brief))
  "Toggle the switch on or off.

OBJ is an instance of `reverso--transient-brief'."
  (setq reverso--prefer-brief
        (null (oref obj value))))

(transient-define-infix reverso--transient-input-infix ()
  :class 'reverso--transient-input
  :description "Input")

(transient-define-infix reverso--transient-translate-language-source ()
  :class 'reverso--transient-language
  :description "Source language"
  :key "s"
  ;; XXX not sure why `:argument' is necessary :(
  :argument "-s"
  :languages (alist-get 'translation reverso--languages))

(transient-define-infix reverso--transient-translate-language-target ()
  :class 'reverso--transient-language
  :description "Target language"
  :key "t"
  :argument "-t"
  :languages (alist-get 'translation reverso--languages)
  :target-languages (alist-get 'translation reverso--languages-compatible)
  :is-target t)

(transient-define-suffix reverso--transient-swap-languages ()
  :transient t
  :key "S"
  :description "Swap languages"
  (interactive)
  (let* ((suffixes (transient-suffixes transient-current-command))
         (source (seq-find (lambda (suffix)
                             (and (reverso--transient-language-p suffix)
                                  (not (oref suffix is-target))))
                           suffixes))
         (target (seq-find (lambda (suffix)
                             (and (reverso--transient-language-p suffix)
                                  (oref suffix is-target)))
                           suffixes))
         (source-value (transient-infix-value source))
         (target-value (transient-infix-value target)))
    (oset source value target-value)
    (oset target value source-value)
    (setq reverso--source-value target-value)
    (setq reverso--target-value source-value)))

(transient-define-infix reverso--transient-breif-infix ()
  :transient t
  :class 'reverso--transient-brief
  :key "b"
  :argument "--brief"
  :description "Brief translation output")

(transient-define-suffix reverso--translate-exec-suffix (input source target &optional is-brief)
  :key "e"
  :description "Translate"
  (interactive (transient-args transient-current-command))
  (reverso--translate
   input source target
   (lambda (data)
     (reverso--with-buffer
       (if is-brief
           (reverso--translate-render-brief input data)
         (reverso--translate-render input data))))))

(transient-define-prefix reverso-translate ()
  "Translate text."
  ["Input"
   ("i" "Input" reverso--transient-input-infix)]
  ["Parameters"
   (reverso--transient-translate-language-source)
   (reverso--transient-translate-language-target)
   (reverso--transient-swap-languages)
   (reverso--transient-breif-infix)]
  ["Actions"
   (reverso--translate-exec-suffix)
   ("q" "Quit" transient-quit-one)])

(transient-define-infix reverso--transient-context-language-source ()
  :class 'reverso--transient-language
  :description "Source language"
  :key "s"
  :argument "-s"
  :languages (alist-get 'context reverso--languages))

(transient-define-infix reverso--transient-context-language-target ()
  :class 'reverso--transient-language
  :description "Target language"
  :key "t"
  :argument "-t"
  :languages (alist-get 'translation reverso--languages)
  :target-languages (alist-get 'context reverso--languages-compatible)
  :is-target t)

(transient-define-suffix reverso--context-exec-suffix (input source target)
  :key "e"
  :description "Find context"
  (interactive (transient-args transient-current-command))
  (reverso--get-context
   input source target
   (lambda (data)
     (reverso--with-buffer
       (reverso--context-render input data source target)
       (setq-local reverso--data data)))))

(transient-define-prefix reverso-context ()
  "Find bilingual concordances for text.

A bilingual concordance is a pair of strings of the same text in
different languages."
  ["Input"
   ("i" "Input" reverso--transient-input-infix)]
  ["Parameters"
   (reverso--transient-context-language-source)
   (reverso--transient-context-language-target)
   (reverso--transient-swap-languages)]
  ["Actions"
   (reverso--context-exec-suffix)
   ("q" "Quit" transient-quit-one)])

(transient-define-infix reverso--transient-synonyms-language ()
  :class 'reverso--transient-language
  :description "Language"
  :key "s"
  :argument "-s"
  :languages (alist-get 'synonyms reverso--languages))

(transient-define-suffix reverso--synonyms-exec-suffix (input source)
  :key "e"
  :description "Find synonyms"
  (interactive (transient-args transient-current-command))
  (reverso--get-synomyms
   input source
   (lambda (data)
     (reverso--with-buffer
       (reverso--synonyms-render input data)
       (setq-local reverso--data data)))))

(transient-define-prefix reverso-synonyms ()
  "Find synomyms."
  ["Input"
   ("i" "Input" reverso--transient-input-infix)]
  ["Parameters"
   (reverso--transient-synonyms-language)]
  ["Actions"
   (reverso--synonyms-exec-suffix)
   ("q" "Quit" transient-quit-one)])

(transient-define-infix reverso--transient-grammar-language ()
  :class 'reverso--transient-language
  :description "Language"
  :key "s"
  :argument "-s"
  :languages (alist-get 'grammar reverso--languages))

(transient-define-suffix reverso--grammar-exec-suffix (input source)
  :key "e"
  :description "Check grammar"
  (interactive (transient-args transient-current-command))
  (reverso--get-grammar
   input source
   (lambda (data)
     (reverso--with-buffer
       (reverso--grammar-render data)
       (setq-local reverso--data data)))))

(transient-define-prefix reverso-grammar ()
  "Check grammar."
  ["Input"
   ("i" "Input" reverso--transient-input-infix)]
  ["Parameters"
   (reverso--transient-grammar-language)]
  ["Actions"
   (reverso--grammar-exec-suffix)
   ("q" "Quit" transient-quit-one)])

(transient-define-prefix reverso ()
  "Translation, grammar checking and bilingual concordances and more."
  ["Commands"
   ("t" "Translation" reverso-translate)
   ("c" "Context" reverso-context)
   ("s" "Synomyms" reverso-synonyms)
   ("g" "Grammar check" reverso-grammar)]
  ["Actions"
   ("q" "Quit" transient-quit-one)
   ("k" "Kek" (lambda () (interactive)
                (message "%s"
                         (cl-mapcan (lambda (obj)
                                      (when (and (slot-exists-p obj 'scope)
                                                 (oref obj scope))
                                        (oref obj scope)))
                                    (transient-suffixes 'reverso)))))]
  (interactive)
  (setq-local reverso--use-buffer-as-input (equal current-prefix-arg '(4)))
  (transient-setup 'reverso))

(provide 'reverso)
;;; reverso.el ends here
