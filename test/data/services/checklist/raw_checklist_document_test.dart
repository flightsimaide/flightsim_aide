import 'package:flightsim_aide/data/services/checklist/model/raw_checklist_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('holds name and text', () {
    const doc = RawChecklistDocument(name: 'a.txt', text: 'body');
    expect(doc.name, 'a.txt');
    expect(doc.text, 'body');
  });
}
