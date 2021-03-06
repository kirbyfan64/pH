import 'package:collection/collection.dart';
import 'package:petitparser/petitparser.dart';

class EvalContext {
  Map<String, String> vars, macroVars;
  EvalContext({this.vars: const {}, this.macroVars});
}

class EvalError implements Exception {
  final String message;
  EvalError(this.message);
  String toString() => message;
}

bool isTruthy(String str) => str != null;

abstract class Expression {
  String eval(EvalContext ctx);
}

enum RelationOp { and, or }

class Relation extends Expression {
  Expression left, right;
  RelationOp op;
  Relation({this.left, this.right, this.op});
  String toString() => 'Relation(left: $left, right: $right, op: $op)';
  bool operator==(other) => other is Relation && left == other.left &&
                            right == other.right && op == other.op;

  String eval(EvalContext ctx) {
    var leftEval = left.eval(ctx);
    switch (op) {
    case RelationOp.and: return isTruthy(leftEval) ? right.eval(ctx) : null;
    case RelationOp.or: return isTruthy(leftEval) ? leftEval : right.eval(ctx);
    }
    return "";
  }
}

enum ComparisonOp { eq, ne }

class Comparison extends Expression {
  Expression left, right;
  ComparisonOp op;
  Comparison({this.left, this.right, this.op});
  String toString() => 'Comparison(left: $left, right: $right, op: $op)';
  bool operator==(other) => other is Comparison && left == other.left &&
                            right == other.right && op == other.op;

  String eval(EvalContext ctx) {
    var leftEval = left.eval(ctx), rightEval = right.eval(ctx);
    bool test;
    switch (op) {
    case ComparisonOp.eq: test = leftEval == rightEval; break;
    case ComparisonOp.ne: test = leftEval != rightEval; break;
    }

    return test ? '' : null;
  }
}

class Negation extends Expression {
  Expression expr;
  Negation(this.expr);
  String toString() => 'Negation($expr)';
  bool operator==(other) => other is Negation && expr == other.expr;

  String eval(EvalContext ctx) => isTruthy(expr.eval(ctx)) ? null : '';
}

class Concat extends Expression {
  Function listEquals = const ListEquality().equals;

  List<Expression> parts;
  bool addSpace;
  Concat(this.parts, {this.addSpace: false});
  String toString() => 'Concat($parts, addSpace: $addSpace)';
  bool operator==(other) => other is Concat && listEquals(parts, other.parts) &&
                            addSpace == other.addSpace;

  String eval(EvalContext ctx) =>
    parts
      .map((p) => p.eval(ctx))
      .where((e) => e != null)
      .join(addSpace ? ' ' : '');
}

class Var extends Expression {
  String name;
  bool isMacroVar, isOptional;
  Var(this.name, {this.isMacroVar: false, this.isOptional: false});
  String toString() => 'Var($name, isMacroVar: $isMacroVar, isOptional: $isOptional)';
  bool operator==(other) => other is Var && name == other.name &&
                            isMacroVar == other.isMacroVar &&
                            isOptional == other.isOptional;
  String get prefixed {
    var prefix = r'$';
    if (isMacroVar) {
      prefix += '@';
    }
    if (isOptional) {
      prefix += '?';
    }
    return prefix + name;
  }

  String eval(EvalContext ctx) {
    var table = isMacroVar ? ctx.macroVars : ctx.vars;
    if (table == null) {
      assert(isMacroVar);
      throw new EvalError('macro var $prefixed requested in non-macro');
    } else if (!table.containsKey(name)) {
      if (isOptional) {
        return null;
      } else {
        throw new EvalError('undefined variable $prefixed');
      }
    } else {
      return table[name];
    }
  }
}

class Text extends Expression {
  String value;
  Text(this.value);
  String toString() => 'Text($value)';
  bool operator==(other) => other is Text && value == other.value;

  String eval(EvalContext ctx) => this.value;
}

class ExprGrammar extends GrammarParser {
  ExprGrammar(): super(const ExprGrammarDefinition());
}

class ExprGrammarDefinition extends GrammarDefinition {
  const ExprGrammarDefinition();

  start() => ref(expr).end();
  token(Parser p) => p.flatten().trim();

  expr() => ref(relExpr);

  relExpr() => ref(cmpExpr) & (ref(relOp) & ref(cmpExpr)).star();
  relOp() => ref(token, string('and') | string('or'));

  cmpExpr() => ref(addExpr) & (ref(cmpOp) & ref(addExpr)).optional();
  cmpOp() => ref(token, string('==') | string('!='));

  addExpr() => ref(concatExpr) & (ref(addOp) & ref(concatExpr)).pick(1).star();
  addOp() => ref(token, string('+'));

  concatExpr() => ref(negExpr).plus();

  negExpr() => ref(token, char('!')).optional() & ref(simpleExpr);

  simpleExpr() => ref(parenExpr) | variable() | value();

  variable() => (var_() | macroVar()).trim();
  var_() => char(r'$') & char('?').optional() & ref(id);
  macroVar() => string(r'$@') & char('?').optional() & ref(id);
  id() => letter() & (word() | anyOf('_-')).star();

  value() => ref(qstring) | ref(bareword);

  qstring() => (mkqstring("'") | mkqstring('"')).trim();
  mkqstring(delim) => string(delim) & mkchar(delim).star() & string(delim);
  mkchar(delim) => ((char('\\') & any()).pick(1) | string(delim).neg());

  bareword() => ref(token, ref(relOp).not() & noneOf('\$"\'+!=()') &
                           (whitespace() | char(')')).neg().star());

  parenExpr() => (char('(') & ref(expr) & char(')')).pick(1);
}

class ExprParser extends GrammarParser {
  ExprParser(): super(const ExprParserDefinition());
}

class ExprParserDefinition extends ExprGrammarDefinition {
  const ExprParserDefinition();

  static const relOpMap = const {
    'and': RelationOp.and,
    'or': RelationOp.or,
  };

  static const cmpOpMap = const {
    '==': ComparisonOp.eq,
    '!=': ComparisonOp.ne,
  };

  relExpr() => super.relExpr().map((p) => p[1].fold(p[0],
                                            (left, q) =>
                                              new Relation(left: left, right: q[1],
                                                           op: q[0])));
  relOp() => super.relOp().map((p) => relOpMap[p]);

  cmpExpr() => super.cmpExpr().map((p) => p[1] == null ? p[0] :
                                            new Comparison(left: p[0], right: p[1][1],
                                                           op: p[1][0]));
  cmpOp() => super.cmpOp().map((p) => cmpOpMap[p]);

  addExpr() => super.addExpr().map((p) => p[1].isEmpty ? p[0] :
                                          new Concat(([p[0]]..addAll(p[1])).cast<Expression>()));

  concatExpr() => super.concatExpr().map((p) => p.length == 1 ? p[0] :
                                                new Concat(p.cast<Expression>(), addSpace: true));

  negExpr() => super.negExpr().map((p) => p[0] == null ? p[1] : new Negation(p[1]));

  var_() => super.var_().map((p) => new Var(p[2], isOptional: p[1] != null));
  macroVar() => super.macroVar().map((p) => new Var(p[2], isMacroVar: true,
                                                    isOptional: p[1] != null));
  id() => super.id().flatten();

  qstring() => super.qstring().map((p) => new Text(p[1].join("")));
  bareword() => super.bareword().map((p) => new Text(p));
}

Expression parseExpression(String expr) {
  var result = new ExprParser().parse(expr);
  if (result is Success) {
    return result.value;
  } else {
    return null;
  }
}
