module DrAmbiguity

import DateTime;
import salix::Core;
import salix::HTML;
import salix::Node;
import salix::Index;
import salix::App;
import salix::lib::Bootstrap;
import lang::rascal::format::Grammar;
import ParseTree;
import IO;
import List;
import Set;
import String;
import Boolean;  
import util::Math;
import Simplify;
import GenerateTrees;
import Detection;
import util::Reflective;
import Util;
import Grammar;
import Diagnose; 
import Brackets;
import GrammarEditor;
import util::Maybe;
import ValueIO;
import vis::Text;

private loc www = |http://localhost:7000/index.html|;
private loc root = |project://drambiguity/src|;

@synopsis{start DrAmbiguity with a fresh grammar and an example input sentence}
App[Model] drAmbiguity(type[&T <: Tree] grammar, loc input) 
  = drAmbiguity(model(grammar, input=readFile(input)));
  
@synopsis{Continue DrAmbiguity with a previously saved project}  
App[Model] drAmbiguity(loc project) 
  = drAmbiguity(readBinaryValueFile(#Model, project));

@synopsis{start DrAmbiguity with a fresh grammar and an example input sentence}
App[Model] drAmbiguity(type[&T <: Tree] grammar, str input) 
  = drAmbiguity(model(grammar, input=input));

@synopsis{start DrAmbiguity with a fresh grammar and no input sentence yet}
App[Model] drAmbiguity(type[&T <: Tree] grammar) 
  = drAmbiguity(model(grammar));
  
@synopsis{start DrAmbiguity with a fresh grammar and a corresponding example (ambiguous) example tree}  
App[Model] drAmbiguity(type[&T <: Tree] grammar, &T input) 
  = drAmbiguity(model(completeLocs(input), grammar));

@synopsis{This is the internal work horse that boots up the Salix application that is called DrAmbiguity.}  
App[Model] drAmbiguity(Model m, str id="DrAmbiguity") 
  = webApp(
      makeApp(
        id, 
        Model () { return m; }, 
        withIndex(
          "Dr Ambiguity", 
          id, 
          view, 
          css=["https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0/css/bootstrap.min.css"], 
          scripts=[
            "https://code.jquery.com/jquery-3.2.1.slim.min.js",
            "https://cdnjs.cloudflare.com/ajax/libs/popper.js/1.12.9/umd/popper.min.js",
            "https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0/js/bootstrap.min.js"
          ]
        ),
        update
      ),
      root
    );

@memo
&T cache(&T t) = t;

data Model 
  = model(type[Tree] grammar,
      str input = "",
      Maybe[Tree] tree = saveParse(grammar, input),
      Maybe[loc] file = just(|home:///myproject.dra|),
      bool inputDirty = false,
      str grammarText = cache(trim(grammar2rascal(Grammar::grammar({}, grammar.definitions)))),
      bool grammarDirty = false,
      str commitMessage = "",
      lrel[datetime stamp, str msg, str grammar] grammarHistory = [<now(), "initial", grammarText>],
      lrel[str input, Symbol nt, Maybe[Tree] tree, str status]  examples = [],
      int generateAmount = 5, 
      list[str] errors = [],
      bool labels = false, 
      bool literals = false,
      bool \layout = false,
      bool chars = true
    );
 
data Msg 
   = labels()
   | literals()
   | \layout()
   | chars()
   | focus()
   | simplify()
   | freshSentence()
   | newInput(str x)
   | selectExample(int count)
   | removeExample(int count)
   | generateAmount(int count)
   | storeInput()
   | newGrammar(str x)
   | commitGrammar(int selector)
   | setStartNonterminal(Symbol s)
   | clearErrors()
   | removeGrammar(int count)
   | saveProject(loc file)
   | loadProject(loc file)
   | filename(loc file)
   | nofilename()
   | commitMessage(str msg)
   ;

Model update(clearErrors(), Model m) = m[errors=[]];
Model update(labels(), Model m) = m[labels = !m.labels];
Model update(literals(), Model m) = m[literals = !m.literals];
Model update(\layout(), Model m) = m[\layout = !m.\layout];
Model update(Msg::chars(), Model m) = m[chars = !m.chars];
Model update(Msg::focus(), Model m) = focus(m);
Model update(Msg::filename(loc f), Model m) = m[file=just(f)];
Model update(nofilename(), Model m) = m[file=nothing()];
Model update(commitMessage(str msg), Model m) = m[commitMessage=msg];
Model update(removeGrammar(int count), Model m) = m[grammarHistory = m.grammarHistory[0..count-1] + m.grammarHistory[count..]];

Model update(loadProject(loc f), Model m) {
  try {
    m = readBinaryValueFile(#Model, f);
    m.errors = [];
    return m;
  } 
  catch value x: {
    m.errors += ["IO exception: <x>"];
    return m;
  }
}

Model update(saveProject(loc f), Model m) {
  writeBinaryValueFile(f, m);
  return m;
}
 
Model update(selectExample(int count), Model m) {
  m.tree = m.examples[count-1].tree;
  // println("new tree: <m.tree>");
  m.grammar = type[Tree] ng := type(m.examples[count-1].nt, m.grammar.definitions) ? ng : m.grammar;
  m.input = m.examples[count-1].input;
  m.inputDirty = true;
  if (m.tree == nothing()) {
    m.errors += ["input sentence has parse error"];
  }
  return m;
}

Model update(removeExample(int count), Model m) = m[examples = m.examples[0..count-1] + m.examples[count..]];
Model update(generateAmount(int count), Model m) = m[generateAmount = count > 0 && count < 101 ? count : m.generateAmount];
Model update(newGrammar(str x), Model m) {
  m.grammarText=x;
  m.grammarDirty=false;
  return m;
}

str status(nothing()) = "error";
str status(just(Tree x)) = "no amb." when /amb(_) !:= x;
default str status(just(Tree x)) = "amb";

Model update(storeInput(), Model m) = m[examples= [<m.input, Util::symbol(m.tree.val), m.tree, status(m.tree)>] + m.examples];

Model update(setStartNonterminal(Symbol s), Model m) {
  if (type[Tree] new := type(s, m.grammar.definitions)) {
    m.grammar = new;
    
    try {
      m.tree = just(reparse(m.grammar, m.input));
      m.inputDirty = false;
      m.errors = [];
    }
    catch ParseError (l) : {
      m.errors += ["parse error in input at <l>"];
      m.tree = nothing();
    }
    catch value v: {
      m.errors += ["unexpected error: <v>"];
      m.tree = nothing();
    }
  }
  
  return m;
}

Model update(Msg::commitGrammar(int selector), Model m) {
  println("committing grammar <selector>");
  try {
    str newGrammar = "";
    
    if (selector == -1) {
      m.grammarHistory = [<now(), m.commitMessage, m.grammarText>] + m.grammarHistory;
      newGrammar = m.grammarText;
      m.grammarDirty = false;
    }
    else {
      newGrammar = m.grammarHistory[selector-1].grammar;
      m.grammarText = m.grammarHistory[selector-1].grammar;
      m.grammarDirty = true;
    }
    
    m.commitMessage = "";
    m.errors = [];
    m.grammar = commitGrammar(m.grammar.symbol, newGrammar);
        
    // then reparse the input
    try {
      m.tree = just(reparse(m.grammar, m.input));
    }
    catch ParseError (l) : {
      m.tree = nothing();
      m.errors += ["parse error in input at <l>"];
    }
    catch value v: {
      m.error += ["unexpected error: <v>"];
      m.tree = nothing();
    }
    
    // and reparse the examples
    m.examples = for (<str ex, Symbol s, Maybe[Tree] t, str st> <- m.examples) {
      try {
        t = reparse(m.grammar, s, ex);
        append <ex, s, just(t), status(just(t))>;
      }
      catch ParseError(e) :
        append <ex, s, nothing(), status(nothing())>;
      catch value v: {
        append <ex, s, nothing(), status(nothing())>;
        m.errors += ["unexpected error: <v>"];
      }  
    }
  }
  catch value x: 
    m.errors += ["grammar could not be processed due to <x>"];
  
  return m;
}

Model update(newInput(str new), Model m) {
  try {
    m.input = new;
    m.tree = saveParse(m.grammar, new);
    m.errors = [];
    m.inputDirty = false;
  }
  catch ParseError(l) : {
    m.errors += ["parse error in input at <l>"];
    m.tree = nothing();
    m.inputDirty = false;
  }
  
  return m;
}

Model update(Msg::simplify(), Model m) {
  saved = m.input;

  gr = type(symbol(m.tree.val), m.grammar.definitions);
  m.tree=just(completeLocs(reparse(gr, simplify(gr, m.tree.val, effort=m.generateAmount * 100))));
  m.input = "<m.tree.val>";
  m.inputDirty = m.input != saved;

  if (!m.inputDirty) {
    m.errors += ["no simpler example found"]; 
  }

  
  return m;
}

Model update(Msg::freshSentence(), Model m) = freshSentences(m);

Model freshSentences(Model m) {
  if (options:{_,*_} := randomAmbiguousSubTrees(m.grammar, m.generateAmount)) {
    new = m.examples == [] ? [*options] : [op | op <- options, !any(e <- m.examples, just(op) := e.tree)];
    if (new != []) {
      m.examples += [<"<n>", Util::symbol(n), just(completeLocs(n)), status(just(n))> | n <- new];
      m.errors = [];
    }
    else {
      m.errors += ["no new ambiguous sentences found; only <size(options)> existing examples."];
    }
    
    return m;
  }
  else {
    Tree n = randomTree(completeGrammar(m.grammar));
    m.input = "<n>";
    m.tree = just(n);
    m.inputDirty = true;
    m.errors += ["no ambiguous sentences found; current input is randomly selected."];

    return m;
  }
}

void graphic(Model m) {
  // for lack of a visual, here we use ascii art:
   if (m.tree is just) {
      if (amb(alts) := m.tree.val) {
        table(class("table"), class("table-hover"), class("table-sm"), () {
          thead(() {
            for (_ <- alts) {
              th(attr("scope", "col"), () {
                text("Alternative");
              });
            }
          });
          tbody(() {
            tr(() {
              for (Tree t <- alts) {
                td(() {
                  pre(() {
                    text(prettyTree(t, characters = m.chars, literals=m.literals, \layout=m.\layout));
                  });
                });
              }
            });       
          }); 
        });
      }
      else {
        pre(() {
          text(prettyTree(m.tree.val, characters = m.chars, literals=m.literals, \layout=m.\layout));
        });
      }
   }
}
 
Msg onNewSentenceInput(str t) = newInput(t);
Msg onNewGrammarInput(str t) = newGrammar(t); 
 
void view(Model m) {
   container(true, () {
    div(() {
      ul(class("nav nav-pills"), id("tabs"), () {
          li(class("nav-item dropdown"), () {
            a(class("nav-link dropdown-toggle"), \data-toggle("dropdown"), role("button"), hasPopup(true), expanded(false), "File");
            fileUI(m);
          });

          li(class("nav-item"),() {
            a(class("nav-link"), href("#grammar"), dataToggle("tab"), "Grammar"); 
          });

          li(class("nav-item active"), () {
            a(class("nav-link"), href("#input"), dataToggle("tab"), "Sentence");
          });

          li(class("nav-item"), () {
            a(class("nav-link"), href("#graphic"), dataToggle("tab"), "Graphic");
          });

          li(class("nav-item"), () {
            a(class("nav-link"), href("#diagnose"), dataToggle("tab"), "Diagnosis"); 
          });
      });
    });
        
    div(class("tab-content"), id("tabs"),  () {
      div(class("tab-pane fade in active"), id("input"), () {
        inputPane(m);
      });
     
      div(class("tab-pane"), id("graphic"), () {
        graphicPane(m);
      });
      
      div(class("tab-pane fade in"), id("grammar"), () {
        grammarPane(m);
      });
      
      div(class("tab-pane fade in"), id("diagnose"), () {
          if (m.tree is just) {
            diagnose(m.tree.val);
          }
          else {
             alertInfo("Diagnosis of ambiguity is unavailable while the input sentence has a parse error.");
          } 
      });
    });
    
    if (m.errors != []) {
      row(() {
        column(10, md(), () {
           for (e <- m.errors) {
            alertDanger(e);
           }
        });
        column(2, md(), () {
          div(class("list-group list-group-flush"), style(<"list-style-type","none">), () {
            button(class("list-group-item"), onClick(clearErrors()), "Clear");
          });
        });
      });
    }
  });
}

Msg onCommitMessageInput(str m) {
  return commitMessage(m);
}

void grammarPane(Model m) {
  row(() {
    column(10, md(), () {
      if (m.grammarDirty) {
        textarea(class("form-control"), style(<"width","100%">), rows(25), onChange(onNewGrammarInput), \value(m.grammarText));
      }
      else {
        textarea(class("form-control"), style(<"width","100%">), rows(25), onChange(onNewGrammarInput), \value(m.grammarText));
      }
    });
    column(2, md(), () {
      input(class("list-group-item"), style(<"width","100%">), \type("text"), onInput(onCommitMessageInput), \value(m.commitMessage));
      if (trim(m.commitMessage) != "") {
        button(class("list-group-item"), onClick(commitGrammar(-1)), "Commit");
      }
      else {
        button(class("list-group-item"), disabled(), "Commit");
      }
    });
  });
  
  if (m.grammarHistory != []) { 
          row(() {
            column(10, md(), () {
              table(class("table"), class("table-hover"), class("table-sm"), () {
                colgroup(() {
                  col(class("col-sm-1"));
                  col(class("col-sm-5"));
                  col(class("col-sm-1"));
                  col(class("col-sm-1"));
                });
                thead(() {
                  th(scope("col"), "Version");
                  th(scope("col"),"Message");
                  th(scope("col"),"Revert");
                  th(scope("col"),"Remove");
                });
                tbody(() {
                  int count = 1;
                  for (<datetime stamp, str msg, str grammar> <- m.grammarHistory) {
                    tr( () {
                      td(printDateTime(stamp, "dd-MM-yyyy HH:mm:ss"));
                      td(msg);
                      td(() {
                           button(class("button"), onClick(commitGrammar(count)), "revert");
                      });
                      td(() {
                         button(class("button"), onClick(removeGrammar(count)), "rm");
                      });
                    });
                    count += 1;
                  }
                });
              });
            });
          });
        } 
}

Msg newAmountInput(int i) {
  return generateAmount(i);
}

Msg loadProjectInput(str file) {
 if (/C:\\fakepath\\<name:.*>/ := file) { 
   return loadProject(|home:///| + name);
 }
 else {
   return loadProject(|home:///| + file);
 }
}

Msg onProjectNameInput(str f) {
  if (trim(f) != "") {
    return filename((|home:///| + f)[extension="dra"]);
  }
  else {
    return nofilename();
  }
}

void fileUI(Model m) {
  div(class("dropdown-menu"), labeledBy("nonterminalChoice"), () {
      input(class("dropdown-item"), \type("text"), onInput(onProjectNameInput), \value(m.file != nothing() ? (m.file.val[extension=""].path[1..]) : ""));
      
      if (m.file != nothing()) {
        button(class("dropdown-item"), onClick(saveProject(m.file.val)), "Save");
      }

      button(class("dropdown-item"), attr("onclick", "document.getElementById(\'loadProjectButton\').click();"), "Load…");
      input(\type("file"), attr("accept",".dra"), style(<"display", "none">), id("loadProjectButton"), onInput(loadProjectInput));
    });
 }
 
void inputPane(Model m) {
   bool isError = m.tree == nothing();
   bool isAmb = m.tree != nothing() && amb(_) := m.tree.val ;
   bool nestedAmb = m.tree != nothing() && (amb({/amb(_), *_}) := m.tree.val || appl(_,/amb(_)) := m.tree.val);
   str  sentence = m.input;
   
   row(() {
          column(10, md(), () {
             if (m.inputDirty) {
               textarea(class("form-control"), style(<"width","100%">), rows(10), onChange(onNewSentenceInput), \value(sentence));
             }
             else {
               textarea(class("form-control"), style(<"width","100%">), rows(10), onChange(onNewSentenceInput));
             } 
          });    
          column(2, md(), () {
            div(class("list-group list-group-flush"), style(<"list-style-type","none">), () {
              span(class("list-group-item"), () {
                if (isError) {
                  alertInfo("This sentence is not a <m.grammar>; it has a parse error");
                } 
                else {
                  alertInfo("This sentence is <if (!isAmb) {>not<}> ambiguous, and it has<if (!nestedAmb) {> no<}> nested ambiguity.");
                }
              });
              if (nestedAmb) {          
                button(class("list-group-item"), onClick(focus()), "Focus on nested");
              }
              if (m.tree is just) {          
                button(class("list-group-item"), onClick(storeInput()), "Stash");
              }
              if (isAmb || nestedAmb) {
                button(class("list-group-item"), onClick(simplify()), "Simplify");
              }
              button(class("list-group-item"), onClick(freshSentence()), "Generate");
              input(class("list-group-item"), \type("range"), \value("5"), min("1"), max("100"), onInput(newAmountInput));
              div(class("list-group-item"), class("dropdown"),  () {
                button(class("btn"), class("btn-secondary"), class("dropdown-toggle"), \type("button"), id("nonterminalChoice"), dropdown(), hasPopup(true), expanded(false), 
                  "Start: <symbol2rascal(m.grammar.symbol)>");
                div(class("dropdown-menu"), labeledBy("nonterminalChoice"), () {
                    for (Symbol x <- sorts(m.grammar)) {
                        button(class("list-group-item"), href("#"), onClick(setStartNonterminal(x)),  "<symbol2rascal(x)>");
                    }
                });
              });
            });
          });
        });
        
        if (m.examples != []) { 
          ruleCount = (0 | it + 1 | /prod(_,_,_) := m.grammar.definitions);
          
          row(() {
            column(10, md(), () {
              table(class("table"), class("table-hover"), class("table-sm"), () {
                colgroup(() {
                  col(class("col-sm-1"));
                  col(class("col-sm-1"));
                  col(class("col-sm-7"));
                  col(class("col-sm-1"));
                });
                thead(() {
                  th(scope("col"), "#");
                  th(scope("col"),"Syntax category");
                  th(scope("col"),"Sentence");
                  th(scope("col"),"Status");
                  th(scope("col"),"Select");
                  th(scope("col"),"Remove");
                });
                tbody(() {
                  int count = 0;
                  for (<inp, exs, t, st> <- m.examples) {
                    
                    tr( () {
                      count += 1;
                      td("<count>");
                      td("<symbol2rascal(exs)>");
                      td(() {
                        pre(() { code(inp); });
                      });
                      td(st);
                      td(() {
                           button(class("button"), onClick(selectExample(count)), "use");
                      });
                      td(() {
                         button(class("button"), onClick(removeExample(count)), "rm");
                      });
                    });
                  }
                });
              });
            });
          });
        } 
}

void graphicPane(Model m) {
  if (m.tree is nothing) {
    alertInfo("Graphical parse tree representation unavailable due to parse error in input sentence.");
    return;
  }
  
  bool isAmb = amb(_) := m.tree.val;
  bool nestedAmb = amb({/amb(_), *_}) := m.tree.val || appl(_,/amb(_)) := m.tree.val;
   
  row(() {
          column(10, md(), () {
            graphic(m);
          });
          column(2, md(), () {
		        div(class("list-group"), style(<"list-style-type","none">), () {
		          span(class("list-group-item"), () {
                  alertInfo("This tree is <if (!isAmb) {>not<}> ambiguous, and it has<if (!nestedAmb) {> no<}> nested ambiguity.");
                });
                if (nestedAmb) {          
                  button(class("list-group-item"), onClick(focus()), "Focus on nested");
                }
		        // div(class("list-group-item"), () { 
		        //   input(\type("checkbox"), checked(m.labels), onClick(labels()));
		        //   text("rules");
		        // });
		        div(class("list-group-item "), () { 
		          input(id("literals"), \type("checkbox"), checked(m.literals), onClick(literals()));
		          text("literals");
		        });
		        div(class("list-group-item"), () { 
		          input(\type("checkbox"), checked(m.\layout), onClick(\layout()));
		          text("layout");
		        });
		        div(class("list-group-item"), () { 
		          input(\type("checkbox"), checked(m.chars), onClick(chars()));
		          text("chars");
		        });
		    });
          });
  });
}

Model focus(Model m) {
  if (m.tree is just) {
    ambs = [a | /Tree a:amb(_) := m.tree.val, a != m.tree.val];
    
    if (ambs != []) {
      m.tree = just(ambs[arbInt(size(ambs))]);
      m.input = "<m.tree.val>";
      m.inputDirty = true;
    }
  }
  
  return m;
}
 
str prodlabel(regular(Symbol s)) = symbol2rascal(s);
str prodlabel(prod(label(str x,_),_,_)) = x;
str prodlabel(prod(_, list[Symbol] args:[*_,lit(_),*_],_)) = "<for (lit(x) <- args) {><x> <}>";
default str prodlabel(prod(Symbol s, _,_ )) = symbol2rascal(s);



