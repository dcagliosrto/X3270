#include "CommandDockWidget.h"
#include <QScrollArea>
#include <QFrame>
#include <QLabel>
#include <QSettings>
#include <QCompleter>
#include <QStringListModel>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QFile>
#include <QCoreApplication>

CommandDockWidget::CommandDockWidget(QWidget *parent)
    : QWidget(parent) {
    setFixedHeight(36);
    setStyleSheet(
        "QWidget { background-color: #252526; color: #cccccc; font-size: 11px; }"
        "QLineEdit { background-color: #3c3c3c; color: #ffffff; border: 1px solid #555555; border-radius: 3px; padding: 2px; }"
        "QPushButton { background-color: #333333; border: 1px solid #454545; border-radius: 3px; padding: 3px 8px; white-space: nowrap; }"
        "QPushButton:hover { background-color: #444444; }"
        "QComboBox { background-color: #333333; border: 1px solid #454545; border-radius: 3px; padding: 2px; }"
    );

    setupUi();
}

void CommandDockWidget::setupUi() {
    QVBoxLayout *rootLayout = new QVBoxLayout(this);
    rootLayout->setContentsMargins(0, 0, 0, 0);

    QScrollArea *scrollArea = new QScrollArea(this);
    scrollArea->setWidgetResizable(true);
    scrollArea->setFrameShape(QFrame::NoFrame);
    scrollArea->setVerticalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    scrollArea->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);

    QWidget *container = new QWidget(scrollArea);
    QHBoxLayout *mainLayout = new QHBoxLayout(container);
    mainLayout->setContentsMargins(8, 4, 8, 4);
    mainLayout->setSpacing(8);
    mainLayout->setSizeConstraint(QLayout::SetMinAndMaxSize);

    // 1. Group Link
    m_linkGroupCombo = new QComboBox(container);
    m_linkGroupCombo->addItems({"  Only This", "  Group A", "  Group B"});
    m_linkGroupCombo->setMinimumWidth(85);
    mainLayout->addWidget(m_linkGroupCombo);

    connect(m_linkGroupCombo, QOverload<int>::of(&QComboBox::currentIndexChanged), this, [this](int idx) {
        if (idx == 1) m_linkGroup = "GroupA";
        else if (idx == 2) m_linkGroup = "GroupB";
        else m_linkGroup = "";
    });

    QFrame *sep1 = new QFrame(container);
    sep1->setFrameShape(QFrame::VLine);
    sep1->setStyleSheet("color: #444444;");
    mainLayout->addWidget(sep1);

    // 2. Navigation & Fast Paths
    m_fastPathsLayout = new QHBoxLayout();
    m_fastPathsLayout->setSpacing(4);

    QStringList navTitles = {"  Prev", "Next  ", "List  ", "New +"};
    QStringList navCmds = {"SWAP PREV", "SWAP NEXT", "SWAP LIST", "START"};

    for (int i = 0; i < navTitles.size(); ++i) {
        QPushButton *btn = new QPushButton(navTitles[i], container);
        btn->setProperty("cmd", navCmds[i]);
        connect(btn, &QPushButton::clicked, this, &CommandDockWidget::onIspfButtonClicked);
        m_fastPathsLayout->addWidget(btn);
    }

    QFrame *sep2 = new QFrame(container);
    sep2->setFrameShape(QFrame::VLine);
    sep2->setStyleSheet("color: #444444;");
    m_fastPathsLayout->addWidget(sep2);

    loadFastPaths();
    mainLayout->addLayout(m_fastPathsLayout);

    // 3. Campo ISPF
    m_ispfField = new QLineEdit(container);
    m_ispfField->setPlaceholderText("ISPF Cmd...");
    m_ispfField->setMinimumWidth(90);
    mainLayout->addWidget(m_ispfField);

    connect(m_ispfField, &QLineEdit::returnPressed, this, &CommandDockWidget::onIspfReturnPressed);

    // 4. Toggles
    m_rulerBtn = new QPushButton("  Ruler", container);
    m_rulerBtn->setToolTip("Toggle Crosshair Ruler");
    connect(m_rulerBtn, &QPushButton::clicked, this, [this]() { emit toggleRulerRequested(); });
    mainLayout->addWidget(m_rulerBtn);

    m_timeMachineBtn = new QPushButton("  Time-Machine", container);
    m_timeMachineBtn->setToolTip("Toggle Screen History (Cmd+Opt+T)");
    connect(m_timeMachineBtn, &QPushButton::clicked, this, [this]() { emit toggleTimeMachineRequested(); });
    mainLayout->addWidget(m_timeMachineBtn);

    mainLayout->addStretch();

    // 5. Campo SSH/OOB
    QLabel *oobLabel = new QLabel("SSH/OOB:", container);
    m_oobField = new QLineEdit(container);
    m_oobField->setPlaceholderText("TSO / System...");
    m_oobField->setMinimumWidth(200);

    // Carica autocompletamento da commands.json
    QStringList completions;
    QFile cmdFile(":/commands.json");
    if (!cmdFile.open(QIODevice::ReadOnly)) {
        cmdFile.setFileName(QCoreApplication::applicationDirPath() + "/../Resources/commands.json");
    }
    if (cmdFile.open(QIODevice::ReadOnly)) {
        QJsonDocument doc = QJsonDocument::fromJson(cmdFile.readAll());
        QJsonArray arr = doc.array();
        for (const auto &val : arr) {
            completions.append(val.toObject()["cmd"].toString());
        }
    }
    QCompleter *completer = new QCompleter(completions, this);
    completer->setCaseSensitivity(Qt::CaseInsensitive);
    m_oobField->setCompleter(completer);

    mainLayout->addWidget(oobLabel);
    mainLayout->addWidget(m_oobField);

    connect(m_oobField, &QLineEdit::returnPressed, this, &CommandDockWidget::onOobReturnPressed);

    scrollArea->setWidget(container);
    rootLayout->addWidget(scrollArea);
}

void CommandDockWidget::loadFastPaths() {
    QSettings settings("DX3270", "CrossPlatform");

    QStringList titles = {"=3.4", "=SDSF", "=2", "=X"};
    QStringList cmds = {"=3.4", "=S;ST", "=2", "=X"};

    for (int i = 0; i < titles.size(); ++i) {
        QPushButton *btn = new QPushButton(titles[i], this);
        btn->setProperty("cmd", cmds[i]);
        connect(btn, &QPushButton::clicked, this, &CommandDockWidget::onIspfButtonClicked);
        m_fastPathsLayout->addWidget(btn);
    }
}

void CommandDockWidget::onIspfButtonClicked() {
    QPushButton *btn = qobject_cast<QPushButton*>(sender());
    if (btn) {
        QString cmd = btn->property("cmd").toString();
        emit ispfCommandRequested(cmd, m_linkGroup);
    }
}

void CommandDockWidget::onIspfReturnPressed() {
    QString text = m_ispfField->text().trimmed();
    if (!text.isEmpty()) {
        emit ispfCommandRequested(text, m_linkGroup);
        m_ispfField->clear();
    }
}

void CommandDockWidget::onOobReturnPressed() {
    QString text = m_oobField->text().trimmed();
    if (!text.isEmpty()) {
        emit oobCommandRequested(text, m_linkGroup);
        m_oobField->clear();
    }
}