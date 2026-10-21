#[allow(dead_code)]
#[derive(Debug, Clone)]
pub enum Expr {
    Int(i64), Float(f64), String(String), Identifier(String), MacroCall(String),
    Call { name: String, args: Vec<Expr> },
    BinaryOp { left: Box<Expr>, op: String, right: Box<Expr> },
    Ref(Box<Expr>),
    Deref(Box<Expr>),
    Array(Vec<Expr>),
    Index { name: String, index: Box<Expr> },
}

#[allow(dead_code)]
#[derive(Debug, Clone)]
pub enum Stmt {
    Assign { name: String, value: Expr },
    IndexAssign { name: String, index: Box<Expr>, value: Expr },
    MacroCall { name: String },
    If { condition: (Expr, String, Expr), then_branch: Vec<Stmt>, else_branch: Option<Vec<Stmt>> },
    Switch { expr: Expr, cases: Vec<(Expr, Vec<Stmt>)>, default: Option<Vec<Stmt>> },
    ForIn { var: String, iterable: Expr, body: Vec<Stmt> },
    While { condition: (Expr, String, Expr), body: Vec<Stmt> },
    For { init: Option<Box<Stmt>>, condition: Option<(Expr, String, Expr)>, increment: Option<Box<Stmt>>, body: Vec<Stmt> },
    Break,
    Continue,
    Return { value: Expr },
    Expr(Expr),
}

#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct AliasDecl { pub name: String, pub body: Vec<Stmt> }

#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct FuncDecl { pub name: String, pub args: Vec<String>, pub body: Vec<Stmt> }

#[allow(dead_code)]
#[derive(Debug, Clone)]
pub enum Item { 
    Use(String), Flag(String), Alias(AliasDecl), Func(FuncDecl), HeaderName(String)
}

#[allow(dead_code)]
#[derive(Debug)]
pub struct Program { pub items: Vec<Item> }
