;; Adapted for Emacs font-lock faces from Wilfred/tree-sitter-elisp
;; at 0cbf0906d9ee707c8c109422fba9cdd17ae13dcf.
;; Update from https://github.com/Wilfred/tree-sitter-elisp/blob/main/queries/highlights.scm

;; When several patterns capture the same node, the last one wins, so
;; a pattern that refines another must come after it.

;; Special forms
[
  "and"
  "catch"
  "cond"
  "condition-case"
  "defconst"
  "defvar"
  "function"
  "if"
  "interactive"
  "lambda"
  "let"
  "let*"
  "or"
  "prog1"
  "prog2"
  "progn"
  "quote"
  "save-current-buffer"
  "save-excursion"
  "save-restriction"
  "setq"
  "setq-default"
  "unwind-protect"
  "while"
] @font-lock-keyword-face

;; Function definitions
[
 "defun"
 "defsubst"
 ] @font-lock-keyword-face
(function_definition name: (symbol) @font-lock-function-name-face)
(function_definition parameters: (list (symbol) @font-lock-variable-name-face))

;; Highlight macro definitions the same way as function definitions.
"defmacro" @font-lock-keyword-face
(macro_definition name: (symbol) @font-lock-function-name-face)
(macro_definition parameters: (list (symbol) @font-lock-variable-name-face))

;; &optional and &rest are argument list markers, not parameters.
;; https://www.gnu.org/software/emacs/manual/html_node/elisp/Argument-List.html
(function_definition
  parameters: (list (symbol) @font-lock-keyword-face
    (#match? @font-lock-keyword-face "^&")))
(macro_definition
  parameters: (list (symbol) @font-lock-keyword-face
    (#match? @font-lock-keyword-face "^&")))

;; The variable defined by defvar or defconst. The anchor restricts
;; this to the first symbol, leaving the initial value alone.
(special_form
  [
    "defconst"
    "defvar"
  ]
  .
  (symbol) @font-lock-variable-name-face)

;; Variables bound by let and let*, written either as (let ((x 1)))
;; or as (let (x)).
(special_form
  [
    "let"
    "let*"
  ]
  .
  (list
    [
      (symbol) @font-lock-variable-name-face
      (list . (symbol) @font-lock-variable-name-face)
    ]))

(comment) @font-lock-comment-face

(integer) @font-lock-number-face
(float) @font-lock-number-face
;; Characters are integers in Emacs Lisp, e.g. ?a is 97.
(char) @font-lock-number-face

(string) @font-lock-string-face

;; Docstrings are strings too, so these come after (string) @string.
(function_definition docstring: (string) @font-lock-string-face)
(macro_definition docstring: (string) @font-lock-string-face)
;; defvar and defconst take the docstring after the initial value, so
;; (defvar foo nil "Doc.") has one but (defvar foo "Value") does not.
(special_form
  [
    "defconst"
    "defvar"
  ]
  .
  (symbol)
  .
  (_)
  .
  (string) @font-lock-string-face)

;; #$ is the name of the file being loaded.
;; https://www.gnu.org/software/emacs/manual/html_node/elisp/Special-Read-Syntax.html
(byte_compiled_file_name) @font-lock-constant-face

[
  "("
  ")"
  "#("
  "#["
  "["
  "]"
] @font-lock-bracket-face

[
  "`"
  "#'"
  "'"
  ","
  ",@"
] @font-lock-operator-face

;; Highlight nil and t as constants, unlike other symbols
[
  "nil"
  "t"
] @font-lock-constant-face

;; Keywords evaluate to themselves, so highlight them as constants too.
;; https://www.gnu.org/software/emacs/manual/html_node/elisp/Constant-Variables.html
((symbol) @font-lock-constant-face
  (#match? @font-lock-constant-face "^:"))
