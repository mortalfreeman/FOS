use crate::ast::*;
use std::collections::HashSet;

pub struct Sema {
    pub errors: Vec<String>,
    declared_vars: HashSet<String>,
    array_vars: HashSet<String>,
    no_sec: bool,
    null_sec: bool,
    filename: String,
}

impl Sema {
    pub fn new(no_sec: bool, null_sec: bool, filename: &str) -> Self {
        Self { errors: Vec::new(), declared_vars: HashSet::new(), array_vars: HashSet::new(), no_sec, null_sec, filename: filename.to_string() }
    }

    pub fn analyze(&mut self, program: &Program) {
        if self.no_sec || self.null_sec { return; }
        for item in &program.items {
            if let Item::Func(func) = item {
                self.declared_vars.clear();
                self.array_vars.clear();
                for arg in &func.args { self.declared_vars.insert(arg.clone()); }
                self.visit_stmts(&func.body);
            }
        }
    }

    fn visit_stmts(&mut self, stmts: &[Stmt]) {
        for stmt in stmts {
            match stmt {
                Stmt::Assign { name, value } => {
                    self.visit_expr(value);
                    self.declared_vars.insert(name.clone());
                    if let Expr::Array(_) = value { self.array_vars.insert(name.clone()); }
                }
                Stmt::IndexAssign { name, index, value } => {
                    if !self.declared_vars.contains(name) { self.errors.push(format!("{}: error: use of undeclared array '{}'", self.filename, name)); }
                    else if !self.array_vars.contains(name) { self.errors.push(format!("{}: error: '{}' is not an array", self.filename, name)); }
                    self.visit_expr(index);
                    self.visit_expr(value);
                }
                Stmt::Expr(expr) => self.visit_expr(expr),
                Stmt::Return { value } => self.visit_expr(value),
                Stmt::MacroCall { .. } | Stmt::Break | Stmt::Continue => {}
                Stmt::If { condition, then_branch, else_branch } => {
                    self.visit_expr(&condition.0); self.visit_expr(&condition.2);
                    let branch_vars = self.declared_vars.clone(); let branch_arrays = self.array_vars.clone();
                    self.visit_stmts(then_branch);
                    if let Some(else_b) = else_branch {
                        self.declared_vars = branch_vars.clone(); self.array_vars = branch_arrays.clone();
                        self.visit_stmts(else_b);
                    }
                    self.declared_vars = branch_vars; self.array_vars = branch_arrays;
                }
                Stmt::While { condition, body } => {
                    self.visit_expr(&condition.0); self.visit_expr(&condition.2);
                    let loop_vars = self.declared_vars.clone(); let loop_arrays = self.array_vars.clone();
                    self.visit_stmts(body);
                    self.declared_vars = loop_vars; self.array_vars = loop_arrays;
                }
                Stmt::For { init, condition, increment, body } => {
                    if let Some(i) = init { self.visit_stmts(&[*(*i).clone()]); }
                    if let Some(c) = condition { self.visit_expr(&c.0); self.visit_expr(&c.2); }
                    let loop_vars = self.declared_vars.clone(); let loop_arrays = self.array_vars.clone();
                    self.visit_stmts(body);
                    if let Some(inc) = increment { self.visit_stmts(&[*(*inc).clone()]); }
                    self.declared_vars = loop_vars; self.array_vars = loop_arrays;
                }
            }
        }
    }

    fn visit_expr(&mut self, expr: &Expr) {
        match expr {
            Expr::Identifier(name) => {
                if !self.declared_vars.contains(name) { self.errors.push(format!("{}: error: use of undeclared variable '{}'", self.filename, name)); }
            }
            Expr::Index { name, index } => {
                if !self.declared_vars.contains(name) { self.errors.push(format!("{}: error: use of undeclared array '{}'", self.filename, name)); }
                else if !self.array_vars.contains(name) { self.errors.push(format!("{}: error: '{}' is not an array", self.filename, name)); }
                self.visit_expr(index);
            }
            Expr::Array(elements) => { for e in elements { self.visit_expr(e); } }
            Expr::BinaryOp { left, op: _, right } => { self.visit_expr(left); self.visit_expr(right); }
            Expr::Call { name: _, args } => { for arg in args { self.visit_expr(arg); } }
            Expr::MacroCall(_) => {}
            _ => {}
        }
    }
}
