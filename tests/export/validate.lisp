;;;; tests/export/validate.lisp
;;;;
;;;; Tests of the schema validator: each keyword of the subset with a valid
;;;; and an invalid fixture, the JSON Pointers of the errors, and the
;;;; refusal of keywords outside the subset.
;;;; Owner: step 3.6 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/tests)

(define-test validator
  :parent cl-ansi-spec
  :description "The JSON Schema subset validator.")

(defun validation-of (schema instance)
  "The errors of INSTANCE against SCHEMA, both JSON texts, as (POINTER MESSAGE) lists."
  (mapcar (lambda (error)
            (list (exports:validation-error-pointer error)
                  (exports:validation-error-message error)))
          (exports:validate-json (cl-ansi-spec/json:parse-json schema)
                                 (cl-ansi-spec/json:parse-json instance))))

(defun pointers-of (schema instance)
  (mapcar #'first (validation-of schema instance)))

(defmacro define-validation-test (name schema &key valid invalid)
  "Test that every text of VALID passes SCHEMA and each (TEXT . POINTERS) of
INVALID fails with exactly the error pointers POINTERS."
  `(define-test ,name
     :parent validator
     (dolist (text ',valid)
       (is equal '() (validation-of ,schema text)))
     (loop for (text . pointers) in ',invalid
           do (is equal pointers (pointers-of ,schema text)))))

(define-validation-test validate-type "{\"type\": \"string\"}"
  :valid ("\"a\"" "\"\"")
  :invalid (("1" "") ("null" "") ("[]" "") ("{}" "") ("true" "")))

(define-validation-test validate-type-integer "{\"type\": \"integer\"}"
  :valid ("0" "-7")
  :invalid (("\"1\"" "") ("true" "")))

(define-validation-test validate-type-boolean-null-array-object
    "{\"type\": [\"boolean\", \"null\"]}"
  :valid ("true" "false" "null")
  :invalid (("0" "") ("[]" "") ("{}" "")))

(define-validation-test validate-type-array "{\"type\": \"array\"}"
  :valid ("[]" "[1, \"a\"]")
  :invalid (("{}" "") ("\"[]\"" "")))

(define-validation-test validate-type-object "{\"type\": \"object\"}"
  :valid ("{}" "{\"a\": 1}")
  :invalid (("[]" "") ("null" "")))

(define-validation-test validate-const "{\"const\": \"chapter\"}"
  :valid ("\"chapter\"")
  :invalid (("\"section\"" "") ("1" "")))

(define-validation-test validate-const-structure "{\"const\": {\"a\": [1, 2]}}"
  :valid ("{\"a\": [1, 2]}")
  :invalid (("{\"a\": [2, 1]}" "") ("{\"a\": [1, 2], \"b\": 1}" "")))

(define-validation-test validate-enum "{\"enum\": [\"a\", 1, null]}"
  :valid ("\"a\"" "1" "null")
  :invalid (("\"b\"" "") ("2" "") ("false" "")))

(define-validation-test validate-required
    "{\"required\": [\"kind\", \"span\"]}"
  :valid ("{\"kind\": 1, \"span\": 2}" "{\"span\": 1, \"kind\": 1, \"x\": 1}"
          ;; not an object: `required` does not apply
          "[]")
  :invalid (("{\"kind\": 1}" "") ("{}" "" "")))

(define-test validate-required-messages
  :parent validator
  (is equal '(("" "missing required property \"b\""))
      (validation-of "{\"required\": [\"a\", \"b\"]}" "{\"a\": 1}")))

(define-validation-test validate-properties
    "{\"properties\": {\"n\": {\"type\": \"integer\"},
                       \"o\": {\"properties\": {\"s\": {\"type\": \"string\"}}}}}"
  :valid ("{}" "{\"n\": 1}" "{\"n\": 1, \"other\": []}" "{\"o\": {\"s\": \"a\"}}")
  :invalid (("{\"n\": \"x\"}" "/n")
            ("{\"o\": {\"s\": 1}}" "/o/s")
            ("{\"n\": null, \"o\": {\"s\": 1}}" "/n" "/o/s")))

(define-validation-test validate-additional-properties-false
    "{\"properties\": {\"a\": {}}, \"additionalProperties\": false}"
  :valid ("{}" "{\"a\": 1}")
  :invalid (("{\"b\": 1}" "/b") ("{\"a\": 1, \"b\": 1, \"c\": 2}" "/b" "/c")))

(define-validation-test validate-additional-properties-schema
    "{\"properties\": {\"a\": {}}, \"additionalProperties\": {\"type\": \"integer\"}}"
  :valid ("{\"a\": \"anything\", \"b\": 1}")
  :invalid (("{\"b\": \"x\"}" "/b") ("{\"a\": 1, \"b\": 1, \"c\": []}" "/c")))

(define-validation-test validate-additional-properties-true
    "{\"additionalProperties\": true}"
  :valid ("{\"x\": 1}")
  :invalid ())

(define-validation-test validate-items
    "{\"type\": \"array\", \"items\": {\"type\": \"integer\"}}"
  :valid ("[]" "[1, 2, 3]")
  :invalid (("[1, \"a\"]" "/1") ("[\"a\", 1, null]" "/0" "/2") ("{}" "")))

(define-validation-test validate-ref
    "{\"$defs\": {\"n\": {\"type\": \"integer\"}},
      \"properties\": {\"a\": {\"$ref\": \"#/$defs/n\"},
                       \"b\": {\"type\": \"array\", \"items\": {\"$ref\": \"#/$defs/n\"}}}}"
  :valid ("{}" "{\"a\": 1, \"b\": [1, 2]}")
  :invalid (("{\"a\": \"x\"}" "/a") ("{\"b\": [1, \"x\"]}" "/b/1")))

(define-validation-test validate-ref-recursive
    "{\"$defs\": {\"node\": {\"type\": \"object\", \"required\": [\"kind\"],
                            \"properties\": {\"children\": {\"type\": \"array\",
                                             \"items\": {\"$ref\": \"#/$defs/node\"}}}}},
      \"$ref\": \"#/$defs/node\"}"
  :valid ("{\"kind\": 1, \"children\": [{\"kind\": 2, \"children\": []}]}")
  :invalid (("{\"kind\": 1, \"children\": [{\"kind\": 2}, {}]}" "/children/1")))

(define-validation-test validate-ref-root
    "{\"type\": \"object\", \"properties\": {\"next\": {\"$ref\": \"#\"}}}"
  :valid ("{\"next\": {\"next\": {}}}")
  :invalid (("{\"next\": {\"next\": 1}}" "/next/next")))

(define-test validate-ref-escapes
  :parent validator
  (is equal '()
      (validation-of "{\"$defs\": {\"a/b~c\": {\"type\": \"integer\"}},
                       \"$ref\": \"#/$defs/a~1b~0c\"}"
                     "1"))
  (is equal '("")
      (pointers-of "{\"$defs\": {\"a/b~c\": {\"type\": \"integer\"}},
                     \"$ref\": \"#/$defs/a~1b~0c\"}"
                   "\"x\"")))

(define-test validate-ref-unresolved
  :parent validator
  (dolist (reference '("#/$defs/missing" "other.json#/x" "#no-slash" "#/$defs/a/b"))
    (fail (validation-of (format nil "{\"$defs\": {\"a\": {}}, \"$ref\": ~S}" reference)
                         "1")
          'exports:unresolved-schema-reference)))

(define-validation-test validate-one-of
    "{\"oneOf\": [{\"type\": \"string\"}, {\"type\": \"integer\"}]}"
  :valid ("\"a\"" "1")
  :invalid (("null" "") ("[]" "")))

(define-test validate-one-of-overlap
  :parent validator
  (is equal '("")
      (pointers-of "{\"oneOf\": [{\"type\": \"integer\"}, {\"const\": 1}]}" "1"))
  (is equal '()
      (validation-of "{\"oneOf\": [{\"type\": \"integer\"}, {\"const\": 1}]}" "2")))

(define-test validate-one-of-enum-with-descriptions
  :parent validator
  (let ((schema "{\"oneOf\": [{\"const\": \"a\", \"description\": \"first\"},
                              {\"const\": \"b\", \"description\": \"second\"}]}"))
    (is equal '() (validation-of schema "\"b\""))
    (is equal '("") (pointers-of schema "\"c\""))))

(defparameter *kind-schema*
  "{\"$defs\": {
      \"chapter\": {\"type\": \"object\", \"required\": [\"kind\", \"title\"],
                    \"properties\": {\"kind\": {\"const\": \"chapter\"},
                                     \"title\": {\"type\": \"string\"}},
                    \"additionalProperties\": false},
      \"text\": {\"type\": \"object\", \"required\": [\"kind\", \"text\"],
                 \"properties\": {\"kind\": {\"const\": \"text\"},
                                  \"text\": {\"type\": \"string\"}},
                 \"additionalProperties\": false}},
    \"type\": \"array\",
    \"items\": {\"oneOf\": [{\"$ref\": \"#/$defs/chapter\"}, {\"$ref\": \"#/$defs/text\"}]}}"
  "A oneOf on \"kind\", the shape the generator emits.")

(define-test validate-one-of-on-kind
  :parent validator
  (is equal '()
      (validation-of *kind-schema*
                     "[{\"kind\": \"chapter\", \"title\": \"t\"}, {\"kind\": \"text\", \"text\": \"x\"}]"))
  ;; errors come from the branch the kind selects, not from every branch
  (is equal '("/1/text")
      (pointers-of *kind-schema*
                   "[{\"kind\": \"chapter\", \"title\": \"t\"}, {\"kind\": \"text\", \"text\": 1}]"))
  (is equal '("/0/extra")
      (pointers-of *kind-schema* "[{\"kind\": \"chapter\", \"title\": \"t\", \"extra\": 1}]"))
  (is equal '(("/0" "missing required property \"title\""))
      (validation-of *kind-schema* "[{\"kind\": \"chapter\"}]"))
  (is equal '(("/0" "unknown kind \"nope\""))
      (validation-of *kind-schema* "[{\"kind\": \"nope\"}]"))
  ;; no kind at all: falls back to the generic message
  (is equal '("/0") (pointers-of *kind-schema* "[{}]"))
  (is equal '("/0") (pointers-of *kind-schema* "[1]")))

(define-test validate-pointer-escaping
  :parent validator
  (is equal '("/a~1b/c~0d")
      (pointers-of "{\"properties\": {\"a/b\": {\"properties\": {\"c~d\": {\"type\": \"integer\"}}}}}"
                   "{\"a/b\": {\"c~d\": \"x\"}}")))

(define-test validate-boolean-schemas
  :parent validator
  (is equal '() (validation-of "{\"properties\": {\"a\": true}}" "{\"a\": 1}"))
  (is equal '("/a") (pointers-of "{\"properties\": {\"a\": false}}" "{\"a\": 1}")))

(define-test validate-annotations-ignored
  :parent validator
  (is equal '()
      (validation-of "{\"$schema\": \"https://json-schema.org/draft/2020-12/schema\",
                       \"$id\": \"x\", \"$comment\": \"c\", \"title\": \"t\",
                       \"description\": \"d\", \"examples\": [1], \"default\": 0,
                       \"type\": \"integer\"}"
                     "1")))

(define-test validate-order-and-multiple-errors
  :parent validator
  ;; type failure stops the instance; other keywords still report together
  (is equal '(("" "expected object, found array"))
      (validation-of "{\"type\": \"object\", \"required\": [\"a\"]}" "[]"))
  (is equal '("/a" "/b" "/c")
      (pointers-of "{\"properties\": {\"a\": {\"type\": \"string\"}, \"b\": {\"type\": \"string\"}},
                      \"additionalProperties\": false}"
                   "{\"a\": 1, \"b\": 2, \"c\": 3}")))

(define-test validate-outside-subset
  :parent validator
  (dolist (keyword '("minimum" "pattern" "anyOf" "allOf" "not" "if" "format"
                     "minItems" "$anchor" "patternProperties" "definitions"))
    (fail (validation-of (format nil "{~S: 1}" keyword) "1")
          'exports:unsupported-schema-keyword))
  ;; also deep inside, where only a walk finds it
  (fail (validation-of "{\"properties\": {\"a\": {\"items\": {\"oneOf\": [{\"pattern\": \"x\"}]}}}}"
                       "{}")
        'exports:unsupported-schema-keyword)
  (is equal '(("/properties/a/items/oneOf/0/pattern" . "pattern"))
      (exports:schema-subset-violations
       (cl-ansi-spec/json:parse-json
        "{\"properties\": {\"a\": {\"items\": {\"oneOf\": [{\"pattern\": \"x\"}]}}}}")))
  ;; property names are not keywords
  (is equal '()
      (exports:schema-subset-violations
       (cl-ansi-spec/json:parse-json
        "{\"properties\": {\"pattern\": {\"type\": \"string\"}, \"minimum\": {}},
          \"$defs\": {\"format\": {}}}"))))

(define-test validate-json-valid-p
  :parent validator
  (let ((schema (cl-ansi-spec/json:parse-json "{\"type\": \"integer\"}")))
    (true (exports:json-valid-p schema 1))
    (false (exports:json-valid-p schema "1"))))

(define-test validate-printed-errors
  :parent validator
  (is string= "/a: expected integer, found string"
      (princ-to-string
       (first (exports:validate-json
               (cl-ansi-spec/json:parse-json
                "{\"properties\": {\"a\": {\"type\": \"integer\"}}}")
               (cl-ansi-spec/json:parse-json "{\"a\": \"x\"}"))))))

(define-test validate-one-of-overlap-with-kind
  :parent validator
  ;; two branches match and the kind selects one of them: still invalid
  (is equal '("")
      (pointers-of "{\"oneOf\": [{\"properties\": {\"kind\": {\"const\": \"a\"}}},
                                {\"type\": \"object\"}]}"
                   "{\"kind\": \"a\"}")))

(define-test validate-circular-references
  :parent validator
  (fail (validation-of "{\"$ref\": \"#\"}" "1") 'exports:circular-schema-reference)
  (fail (validation-of "{\"$defs\": {\"a\": {\"$ref\": \"#/$defs/b\"},
                                     \"b\": {\"$ref\": \"#/$defs/a\"}},
                         \"$ref\": \"#/$defs/a\"}" "1")
        'exports:circular-schema-reference)
  (fail (validation-of "{\"$defs\": {\"a\": {\"$ref\": \"#/$defs/a\"}},
                         \"oneOf\": [{\"$ref\": \"#/$defs/a\"}]}" "{\"kind\": \"x\"}")
        'exports:circular-schema-reference))

(define-test validate-malformed-keyword-values
  :parent validator
  (dolist (schema '("{\"items\": [{}]}" "{\"properties\": true}" "{\"oneOf\": {}}"
                    "{\"oneOf\": [1]}" "{\"type\": 1}" "{\"required\": \"a\"}"
                    "{\"enum\": 1}" "{\"$ref\": 1}" "{\"additionalProperties\": 1}"
                    "{\"properties\": {\"a\": 1}}"))
    (fail (validation-of schema "1") 'exports:unsupported-schema-keyword)))

(define-test validate-enum-objects-ignore-member-order
  :parent validator
  (is equal '()
      (validation-of "{\"enum\": [{\"a\": 1, \"b\": 2}]}" "{\"b\": 2, \"a\": 1}")))
