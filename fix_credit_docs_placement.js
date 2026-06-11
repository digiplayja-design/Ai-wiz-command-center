const fs = require('fs');
const dartPath = 'lib/main.dart';
let code = fs.readFileSync(dartPath, 'utf8');

// Step 1: Remove the misplaced download card code from _generate()
// It's between "setState(() {\n        _featuredAnswerDismissed = false;" and "_speakConsiderItDone();"
const badStart = '\n\n        // Credit Docs: Show PDF + DOCX download buttons if available\n        final String? _pdfBase64 = data[\'pdf_base64\'] as String?;';
const badEnd = '        }\n\n        _speakConsiderItDone();';
const badEndAlt = '        }\n        _speakConsiderItDone();';

const badIdx = code.indexOf(badStart);
if (badIdx === -1) { console.error('ERROR: Could not find misplaced credit docs code'); process.exit(1); }

// Find the end of the bad block
let endIdx = code.indexOf(badEnd, badIdx);
const endLen = badEnd.length;
if (endIdx === -1) {
  endIdx = code.indexOf(badEndAlt, badIdx);
  if (endIdx === -1) { console.error('ERROR: Could not find end of bad block'); process.exit(1); }
}
// Remove just the download card block, keep _speakConsiderItDone()
code = code.slice(0, badIdx) + '\n\n        _speakConsiderItDone();' + code.slice(endIdx + endLen);
console.log('Step 1 done: removed misplaced code from _generate()');

// Step 2: Find the correct location in _generateWithUpload()
// The anchor is: allowPdf: false,\n        ),\n      );\n    }); inside _generateWithUpload
const uploadFuncIdx = code.indexOf('Future<void> _generateWithUpload() async {');
if (uploadFuncIdx === -1) { console.error('ERROR: _generateWithUpload not found'); process.exit(1); }

// Find allowPdf: false inside _generateWithUpload
const allowPdfIdx = code.indexOf('allowPdf: false,', uploadFuncIdx);
if (allowPdfIdx === -1) { console.error('ERROR: allowPdf not found in upload func'); process.exit(1); }

// Find the setState closing }); after allowPdf
let setStateClose = code.indexOf('\n    });', allowPdfIdx);
if (setStateClose === -1) { setStateClose = code.indexOf('\n      });', allowPdfIdx); }
if (setStateClose === -1) { console.error('ERROR: setState close not found'); process.exit(1); }

// Determine close length
const closeStr = code.slice(setStateClose, setStateClose + 10);
const closeLen2 = closeStr.startsWith('\n      });') ? '\n      });'.length : '\n    });'.length;
const afterSetState = setStateClose + closeLen2;

console.log('Inserting after setState at index:', afterSetState);
console.log('Context:', JSON.stringify(code.slice(afterSetState - 20, afterSetState + 50)));

// Step 3: Insert download card code in the correct location
// Get the data variable name used in _generateWithUpload
// From screenshot: final data = _decodeKorlixJsonMap(response);
const insertCode = `

        // Credit Docs: Show PDF + DOCX download buttons if available
        final String? _pdfBase64 = data['pdf_base64'] as String?;
        final String? _docxBase64 = data['docx_base64'] as String?;
        if (_pdfBase64 != null && _pdfBase64.isNotEmpty) {
          setState(() {
            _results.insert(
              0,
              GeneratedItem(
                command: '__DOWNLOAD_CARD__',
                title: 'Credit Dispute Letter Downloads',
                content: '__DOWNLOAD_CARD__|' + _pdfBase64 + '|' + (_docxBase64 ?? ''),
                language: _selectedLanguage,
                allowPdf: false,
              ),
            );
          });
        }`;

code = code.slice(0, afterSetState) + insertCode + code.slice(afterSetState);
console.log('Step 2 done: download card code inserted in _generateWithUpload()');

fs.writeFileSync(dartPath, code, 'utf8');
console.log('Fix applied successfully!');
