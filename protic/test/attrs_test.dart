import 'package:test/test.dart';
import 'utils.dart';

void main() {
  test('+# works', () {
    expect('<div +#my-id>', compilesTo('<div id="my-id">'));
  });

  test('+. works', () {
    expect('<div +.a>', compilesTo('<div class="a">'));
    expect('<div +.a +.b>', compilesTo('<div class="a b" >'));
    expect('<div class="a b" +.c +.d>', compilesTo('<div class="a b c d"  >'));
  });

  test('invalid attributes are handled', () {
    expect('<div +>', compilesWithErrors(['invalid attribute']));
    expect('<div +#>', compilesWithErrors(['invalid attribute']));
  });

  test('+attr works', () {
    expect(r'<div +style="width: $width">',
           compilesTo('<div style="width: 10px">', vars: {'width': '10px'}));
  });
}
