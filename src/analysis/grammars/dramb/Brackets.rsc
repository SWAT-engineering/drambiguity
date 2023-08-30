module analysis::grammars::dramb::Brackets

import analysis::grammars::dramb::Util;
import ParseTree;

Production rule(Symbol s) = prod(label("bracket", s), [lit("("), layouts("*default*"), s, layouts("*default*"), lit(")")], {});
Production bo() = prod(lit("("),[\char-class([range(40,40)])], {});
Production bc() = prod(lit(")"),[\char-class([range(41,41)])], {});
Production la() = prod(layouts("*default*"), [], {});

Tree wrap(Tree x) = appl(rule(analysis::grammars::dramb::Util::symbol(x)), [appl(bo(), [char(40)]), appl(la(), []), x, appl(la(), []), appl(bc(), [char(41)])]);

list[Tree] wrap(Symbol s, list[Tree] args) = [ delabel(symbol(a)) == s ? wrap(a) : a | a <- args];

@synopsis{Adds a bracket rule around all directly recursive non-terminals (expressions)} 
Tree brackets(Tree t) = visit(t) {
  case appl(p, args) => appl(p, wrap(delabel(p.def), args))
};
