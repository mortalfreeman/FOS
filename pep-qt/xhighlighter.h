#pragma once
#include <QSyntaxHighlighter>
#include <QTextCharFormat>
#include <QRegularExpression>

class XHighlighter : public QSyntaxHighlighter {
    Q_OBJECT
public:
    explicit XHighlighter(QTextDocument *parent = nullptr);
protected:
    void highlightBlock(const QString &text) override;
private:
    struct HighlightingRule { QRegularExpression pattern; QTextCharFormat format; };
    QVector<HighlightingRule> highlightingRules;
    QTextCharFormat commentFormat;
};
