const fs = require('fs');
const dartPath = 'lib/main.dart';
let code = fs.readFileSync(dartPath, 'utf8');

const uploadFuncIdx = code.indexOf('Future<void> _generateWithUpload() async {');
if (uploadFuncIdx === -1) { console.error('ERROR: _generateWithUpload not found'); process.exit(1); }

let insertAnchorIdx = -1;
const anchors = [
  'content: content,\n            language: _selectedLanguage,\n            allowPdf: false,',
  'content: content,\n          language: _selectedLanguage,\n          allowPdf: false,',
  'content: content,\n              language: _selectedLanguage,\n              allowPdf: false,',
];
for (const anchor of anchors) {
  const idx = code.indexOf(anchor, uploadFuncIdx);
  if (idx !== -1) { insertAnchorIdx = idx; break; }
}
if (insertAnchorIdx === -1) {
  insertAnchorIdx = code.indexOf('allowPdf: false,', uploadFuncIdx);
  if (insertAnchorIdx === -1) { console.error('ERROR: anchor not found'); process.exit(1); }
}

let setStateClose = code.indexOf('\n    });', insertAnchorIdx);
if (setStateClose === -1) setStateClose = code.indexOf('\n      });', insertAnchorIdx);
if (setStateClose === -1) { console.error('ERROR: setState close not found'); process.exit(1); }
const closeLen = code[setStateClose + 1] === ' ' && code[setStateClose + 2] === ' ' && code[setStateClose + 3] === ' ' && code[setStateClose + 4] === ' ' && code[setStateClose + 5] === ' ' && code[setStateClose + 6] === ' ' ? '\n      });'.length : '\n    });'.length;
const afterSetState = setStateClose + closeLen;

const downloadInsert = `

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

code = code.slice(0, afterSetState) + downloadInsert + code.slice(afterSetState);
console.log('Step 1 done');

const mockCardIdx = code.indexOf('Widget _buildMockupFeaturedCharacterCard()');
if (mockCardIdx === -1) { console.error('ERROR: _buildMockupFeaturedCharacterCard not found'); process.exit(1); }

const helpers = `
  Widget _buildCreditDownloadCard(String pdfBase64, String docxBase64) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4A90D9), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.description_rounded, color: Color(0xFF4A90D9), size: 22),
            const SizedBox(width: 8),
            const Expanded(child: Text('Credit Dispute Letter Ready',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
          ]),
          const SizedBox(height: 6),
          const Text('Download your print-ready dispute letter:',
            style: TextStyle(color: Color(0xFFB0BEC5), fontSize: 12)),
          const SizedBox(height: 14),
          if (pdfBase64.isNotEmpty)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB71C1C),
                foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
              label: const Text('Download PDF', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => _saveCreditDocFile(pdfBase64, 'credit_dispute_letter.pdf'),
            ),
          if (pdfBase64.isNotEmpty) const SizedBox(height: 8),
          if (docxBase64.isNotEmpty)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              icon: const Icon(Icons.article_rounded, size: 20),
              label: const Text('Download Word Doc', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => _saveCreditDocFile(docxBase64, 'credit_dispute_letter.docx'),
            ),
        ],
      ),
    );
  }

  Future<void> _saveCreditDocFile(String base64Data, String fileName) async {
    try {
      final bytes = base64Decode(base64Data);
      await Share.shareXFiles([XFile.fromData(bytes, name: fileName,
        mimeType: fileName.endsWith('.pdf') ? 'application/pdf'
          : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')],
        text: 'Credit Dispute Letter');
    } catch (e) { debugPrint('[CreditDocs] Save error: ' + e.toString()); }
  }

`;

code = code.slice(0, mockCardIdx) + helpers + code.slice(mockCardIdx);
console.log('Step 2 done');

const resultCardIdx = code.indexOf('Widget _buildResultCard(GeneratedItem item) {');
if (resultCardIdx === -1) { console.error('ERROR: _buildResultCard not found'); process.exit(1); }
const resultCardBrace = code.indexOf('{', resultCardIdx);
const resultCardFirstLine = code.indexOf('\n', resultCardBrace) + 1;

const check = `
    if (item.command == '__DOWNLOAD_CARD__') {
      final parts = item.content.split('|');
      final pdfB64 = parts.length > 1 ? parts[1] : '';
      final docxB64 = parts.length > 2 ? parts[2] : '';
      return _buildCreditDownloadCard(pdfB64, docxB64);
    }
`;

code = code.slice(0, resultCardFirstLine) + check + code.slice(resultCardFirstLine);
console.log('Step 3 done');

fs.writeFileSync(dartPath, code, 'utf8');
console.log('Flutter credit docs patch applied successfully!');
