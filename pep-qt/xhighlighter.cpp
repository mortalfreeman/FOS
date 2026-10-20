#include "xhighlighter.h"

XHighlighter::XHighlighter(QTextDocument *parent) : QSyntaxHighlighter(parent) {
    HighlightingRule rule;
    
    // Ключевые слова
    QTextCharFormat keywordFormat;
    keywordFormat.setForeground(QColor(100, 200, 255));
    keywordFormat.setFontWeight(QFont::Bold);
    QStringList keywordPatterns = {"\\bfunc\\b", "\\bcon\\b", "\\bif\\b", "\\belse\\b", "\\bwhile\\b", "\\bfor\\b", "\\breturn\\b", "\\buse\\b", "\\balias\\b"};
    for (const QString &pattern : keywordPatterns) {
        rule.pattern = QRegularExpression(pattern);
        rule.format = keywordFormat;
        highlightingRules.append(rule);
    }

    // Строки
    QTextCharFormat stringFormat;
    stringFormat.setForeground(QColor(150, 255, 150));
    rule.pattern = QRegularExpression("\"[^\"]*\"");
    rule.format = stringFormat;
    highlightingRules.append(rule);

    // Макросы $alias, $ping
    QTextCharFormat macroFormat;
    macroFormat.setForeground(QColor(255, 150, 255));
    rule.pattern = QRegularExpression("\\$[a-zA-Z_][a-zA-Z0-9_]*");
    rule.format = macroFormat;
    highlightingRules.append(rule);

    // Числа
    QTextCharFormat numberFormat;
    numberFormat.setForeground(QColor(255, 200, 100));
    rule.pattern = QRegularExpression("\\b[0-9]+(\\.[0-9]+)?\\b");
    rule.format = numberFormat;
    highlightingRules.append(rule);

    // Комментарии !...!
    commentFormat.setForeground(QColor(120, 120, 140));
    commentFormat.setFontItalic(true);
}

void XHighlighter::highlightBlock(const QString &text) {
    for (const HighlightingRule &rule : qAsConst(highlightingRules)) {
        QRegularExpressionMatchIterator matchIterator = rule.pattern.globalMatch(text);
        while (matchIterator.hasNext()) {
            QRegularExpressionMatch match = matchIterator.next();
            setFormat(match.capturedStart(), match.capturedLength(), rule.format);
        }
    }

    // Инлайновые комментарии
    QRegularExpression commentStart("!");
    QRegularExpressionMatchIterator startIt = commentStart.globalMatch(text);
    while (startIt.hasNext()) {
        QRegularExpressionMatch startMatch = startIt.next();
        int start = startMatch.capturedStart();
        int end = text.indexOf("!", start + 1);
        if (end != -1) {
            setFormat(start, end - start + 1, commentFormat);
        }
    }
}
