bool isIdsLoginForm({required String url, required String body}) {
  final uri = Uri.tryParse(url);
  if (uri?.host.toLowerCase() != 'ids.uwh.edu.cn' ||
      uri?.path.toLowerCase().contains('/authserver/login') != true) {
    return false;
  }

  final html = body.toLowerCase();
  final hasUsername = RegExp(
    r'''<input[^>]+(?:name|id)=["']username["']''',
  ).hasMatch(html);
  final hasPassword = RegExp(
    r'''<input[^>]+(?:name|id)=["']password["']|<input[^>]+type=["']password["']''',
  ).hasMatch(html);
  return hasUsername && hasPassword;
}

bool isIdsLoginUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri?.host.toLowerCase() == 'ids.uwh.edu.cn' &&
      uri?.path.toLowerCase().contains('/authserver/login') == true;
}

/// Shared by credential capture, autofill, and runtime login detection.
/// Scope to the password form: the IDS document repeats username IDs in
/// hidden phone/FIDO forms. The encrypted hidden password is not an input.
const idsCredentialFieldsScript = r'''
function idsFieldIsVisible(el) {
  if (!el || el.disabled || el.type === 'hidden' ||
      !el.getClientRects().length) return false;
  var rect = el.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) return false;
  for (var node = el; node && node.nodeType === 1; node = node.parentElement) {
    var style = getComputedStyle(node);
    if (node.hidden || node.inert || style.display === 'none' ||
        style.visibility === 'hidden' || style.visibility === 'collapse' ||
        Number(style.opacity) === 0 || style.pointerEvents === 'none') return false;
  }
  return true;
}
function idsCredentialFields() {
  function fields(scope) {
    return {
      u: scope.querySelector('#username') || scope.querySelector('input[name="username"]'),
      p: scope.querySelector('#password') || scope.querySelector('input[type="password"]'),
      scope: scope
    };
  }
  var forms = document.querySelectorAll('form#pwdFromId');
  for (var i = 0; i < forms.length; i++) {
    var candidate = fields(forms[i]);
    if (idsFieldIsVisible(candidate.u) && idsFieldIsVisible(candidate.p)) return candidate;
  }
  return fields(forms.length ? forms[0] : document);
}
''';

/// The site's raw template has readonly password inputs. Autofill writes the
/// value through the same DOM fields, so readonly alone is not a reliable
/// discriminator. Require the live password form to actually be displayed.
const idsVisibleLoginFormScript =
    '(function(){$idsCredentialFieldsScript'
    r'''
  if (location.hostname.toLowerCase() !== 'ids.uwh.edu.cn' ||
      location.pathname.toLowerCase().indexOf('/authserver/login') < 0) return false;
  var fields = idsCredentialFields();
  return idsFieldIsVisible(fields.u) && idsFieldIsVisible(fields.p);
})()
''';
