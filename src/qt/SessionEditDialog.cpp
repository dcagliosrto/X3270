#include "SessionEditDialog.h"
#include <QVBoxLayout>
#include <QFormLayout>
#include <QHBoxLayout>
#include <QPushButton>

SessionEditDialog::SessionEditDialog(const DXSessionConfig *config, QWidget *parent)
    : QDialog(parent) {

    m_isNew = (config == nullptr);
    setWindowTitle(m_isNew ? "Add New Session" : "Edit Session");
    setMinimumWidth(400);

    setupUi();

    if (config) {
        m_nameField->setText(config->name);
        m_hostField->setText(config->host);
        m_portField->setText(QString::number(config->port));
        m_sslCheck->setChecked(config->useSSL);
        m_verifyCertCheck->setChecked(config->verifyCert);
        m_caField->setText(config->caBundle);
        m_protocolCombo->setCurrentIndex(config->protocol);
        onProtocolChanged(config->protocol);

        m_codePageCombo->setCurrentIndex(static_cast<int>(config->codePage));
        m_modelCombo->setCurrentIndex(static_cast<int>(config->model));
    }
}

void SessionEditDialog::setupUi() {
    QVBoxLayout *mainLayout = new QVBoxLayout(this);
    QFormLayout *formLayout = new QFormLayout();

    m_nameField = new QLineEdit(this);
    m_nameField->setPlaceholderText("e.g. Production Mainframe");

    m_hostField = new QLineEdit(this);
    m_hostField->setPlaceholderText("hostname or IP");

    m_portField = new QLineEdit("23", this);
    m_portField->setMaximumWidth(80);

    m_sslCheck = new QCheckBox("Use SSL/TLS", this);
    m_verifyCertCheck = new QCheckBox("Verify SSL Certificate", this);
    m_verifyCertCheck->setChecked(true);
    m_verifyCertCheck->setEnabled(false);

    m_caField = new QLineEdit(this);
    m_caField->setPlaceholderText("(optional) path to CA bundle .pem");
    m_caField->setEnabled(false);

    m_protocolCombo = new QComboBox(this);
    m_protocolCombo->addItems({"TN3270 - Mainframe (z/OS)", "TN5250 - Midrange (IBM i / AS400)"});

    m_codePageCombo = new QComboBox(this);
    m_codePageCombo->addItems({
        "CP037 (US/Canada)", "CP500 (International)", "CP1047 (Open Systems)",
        "CP280 (Italy)", "CP273 (Germany)", "CP284 (Spain)", "CP285 (United Kingdom)"
    });

    m_modelCombo = new QComboBox(this);
    onProtocolChanged(0);

    formLayout->addRow("Name:", m_nameField);
    formLayout->addRow("Host:", m_hostField);
    formLayout->addRow("Port:", m_portField);
    formLayout->addRow("", m_sslCheck);
    formLayout->addRow("", m_verifyCertCheck);
    formLayout->addRow("CA Bundle:", m_caField);
    formLayout->addRow("Protocol:", m_protocolCombo);
    formLayout->addRow("Screen Model:", m_modelCombo);
    formLayout->addRow("Code Page:", m_codePageCombo);

    mainLayout->addLayout(formLayout);

    QHBoxLayout *btnLayout = new QHBoxLayout();
    QPushButton *cancelBtn = new QPushButton("Cancel", this);
    QPushButton *saveBtn = new QPushButton("Save", this);
    saveBtn->setDefault(true);

    btnLayout->addStretch();
    btnLayout->addWidget(cancelBtn);
    btnLayout->addWidget(saveBtn);
    mainLayout->addLayout(btnLayout);

    connect(m_sslCheck, &QCheckBox::toggled, this, &SessionEditDialog::onSslToggled);
    connect(m_protocolCombo, QOverload<int>::of(&QComboBox::currentIndexChanged), this, &SessionEditDialog::onProtocolChanged);
    connect(cancelBtn, &QPushButton::clicked, this, &QDialog::reject);
    connect(saveBtn, &QPushButton::clicked, this, &QDialog::accept);
}

void SessionEditDialog::onSslToggled(bool checked) {
    m_verifyCertCheck->setEnabled(checked);
    m_caField->setEnabled(checked);
    if (checked && m_portField->text() == "23") m_portField->setText("992");
    else if (!checked && m_portField->text() == "992") m_portField->setText("23");
}

void SessionEditDialog::onProtocolChanged(int index) {
    m_modelCombo->clear();
    if (index == 1) { // 5250
        m_modelCombo->addItems({"Standard - 24x80", "Wide - 27x132"});
    } else {          // 3270
        m_modelCombo->addItems({"Model 2 - 24x80 (default)", "Model 3 - 32x80", "Model 4 - 43x80", "Model 5 - 27x132 (wide)", "Large - 62x160"});
    }
}

DXSessionConfig SessionEditDialog::getSessionConfig() const {
    DXSessionConfig cfg;
    cfg.name = m_nameField->text().trimmed();
    cfg.host = m_hostField->text().trimmed();
    cfg.port = m_portField->text().toUShort();
    cfg.useSSL = m_sslCheck->isChecked();
    cfg.verifyCert = m_verifyCertCheck->isChecked();
    cfg.caBundle = m_caField->text().trimmed();
    cfg.protocol = m_protocolCombo->currentIndex();
    cfg.model = static_cast<x3270::TerminalModel>(m_modelCombo->currentIndex());
    cfg.codePage = static_cast<x3270::CodePage>(m_codePageCombo->currentIndex());
    return cfg;
}