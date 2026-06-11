const fs = require('fs');
let code = fs.readFileSync('lib/main.dart', 'utf8');

// CONFIRMED from screenshots:
// _generateWithUpload() structure:
//   final data = _decodeKorlixJsonMap(response);  [line ~4750]
//   ...
//   final content = (data['content'] ?? data['answer'] ?? '').toString();
//   ...
//   setState(() {
//     _loading = false;
//     _controller.clear();
//     _pickedUploadFile = null;
//     _pickedUploadFiles.clear();
//     _results.insert(0, GeneratedItem(
//       command: ...,
//       title: title,
//       content: content,
//       language: _selectedLanguage,
//       allowPdf: false,
//     ));
//   });
//   } catch (error) {   <-- this is what comes right after
//
// So the anchor for insertion is: the line BEFORE "} catch (error) {" inside _generateWithUpload

const uploadFuncIdx = code.indexOf('Future<void> _generateWithUpload() async {');
if (uploadFuncIdx === -1) { console.error('ERROR: _generateWithUpload not found'); process.exit(1); }

// Find the catch block inside _generateWithUpload
const catchIdx = code.indexOf('} catch (error) {', uploadFuncIdx);
if (catchIdx === -1) { console.error('ERROR: catch block not found'); process.exit(1); }

// Find the line start of the catch block
const catchLineStart = code.lastIndexOf('\n', catchIdx);
console.log('catch block at index:', catchIdx);
console.log('Context before catch:', JSON.stringify(code.slice(catchIdx - 60, catchIdx + 20)));

// Insert download card code just before the catch block
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
        }
`;

code = code.slice(0, catchLineStart) + '\n' + downloadInsert + code.slice(catchLineStart);
console.log('Step 1 done: download card inserted before catch in _generateWithUpload');

// Add helper widgets before _buildMockupFeaturedCharacterCard
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
console.log('Step 2 done: helper widgets added');

// Add check at top of _buildResultCard
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
console.log('Step 3 done: download card check added to _buildResultCard');

fs.writeFileSync('lib/main.dart', code, 'utf8');
console.log('Patch v3 applied successfully!');
