#include "TimeMachineHUDWidget.h"
#include "TimeMachineManager.h"
#include <QHBoxLayout>
#include <QDateTime>
#include <QGuiApplication>

TimeMachineHUDWidget::TimeMachineHUDWidget(QWidget *parent)
    : QWidget(parent) {

    setFixedHeight(38);
    setStyleSheet(
        "QWidget#TimeMachineHUD { background-color: rgba(25, 25, 25, 220); border-radius: 10px; border: 1px solid rgba(255, 255, 255, 40); }"
        "QPushButton { background-color: rgba(255, 255, 255, 20); color: #ffffff; border: 1px solid rgba(255, 255, 255, 30); border-radius: 4px; padding: 2px 8px; font-size: 11px; font-weight: 500; }"
        "QPushButton:hover { background-color: #007acc; border-color: #0099ff; }"
        "QPushButton:checked { background-color: #e67e22; border-color: #d35400; color: #ffffff; }"
        "QSlider::groove:horizontal { height: 4px; background: rgba(255, 255, 255, 30); border-radius: 2px; }"
        "QSlider::handle:horizontal { background: #007acc; width: 12px; margin: -4px 0; border-radius: 6px; }"
        "QLineEdit { background-color: rgba(0, 0, 0, 150); color: #ffffff; border: 1px solid rgba(255, 255, 255, 30); border-radius: 4px; padding: 2px 6px; font-size: 11px; }"
        "QLabel { color: #ffffff; font-family: monospace; font-size: 11px; }"
    );
    setObjectName("TimeMachineHUD");

    setupUi();
}

void TimeMachineHUDWidget::setupUi() {
    QHBoxLayout *layout = new QHBoxLayout(this);
    layout->setContentsMargins(10, 4, 10, 4);
    layout->setSpacing(6);

    m_prevBtn = new QPushButton("<", this);
    m_nextBtn = new QPushButton(">", this);

    m_slider = new QSlider(Qt::Horizontal, this);
    m_slider->setMinimum(0);
    m_slider->setMaximum(1);
    m_slider->setFixedWidth(120);

    m_infoLabel = new QLabel("--:--:-- (#0/0)", this);
    m_infoLabel->setAlignment(Qt::AlignCenter);

    m_prevPinBtn = new QPushButton("|<", this);
    m_prevPinBtn->setToolTip("Jump to Previous PIN");
    m_pinBtn = new QPushButton("PIN", this);
    m_pinBtn->setCheckable(true);
    m_pinBtn->setToolTip("Bookmark Current Frame");
    m_nextPinBtn = new QPushButton(">|", this);
    m_nextPinBtn->setToolTip("Jump to Next PIN");

    m_exportBtn = new QPushButton("Export", this);
    m_importBtn = new QPushButton("Import", this);

    m_searchField = new QLineEdit(this);
    m_searchField->setPlaceholderText("Search...");
    m_searchField->setFixedWidth(90);

    m_diffBtn = new QPushButton("DIFF", this);
    m_diffBtn->setCheckable(true);

    m_liveBtn = new QPushButton("LIVE >>", this);
    m_liveBtn->setStyleSheet("QPushButton { background-color: #27ae60; font-weight: bold; border-color: #2ecc71; } QPushButton:hover { background-color: #2ecc71; }");

    layout->addWidget(m_prevBtn);
    layout->addWidget(m_nextBtn);
    layout->addWidget(m_slider);
    layout->addWidget(m_infoLabel);
    layout->addWidget(m_prevPinBtn);
    layout->addWidget(m_pinBtn);
    layout->addWidget(m_nextPinBtn);
    layout->addWidget(m_exportBtn);
    layout->addWidget(m_importBtn);
    layout->addWidget(m_searchField);
    layout->addWidget(m_diffBtn);
    layout->addWidget(m_liveBtn);

    connect(m_slider, &QSlider::valueChanged, this, &TimeMachineHUDWidget::onSliderValueChanged);
    connect(m_prevBtn, &QPushButton::clicked, this, [this]() {
        if (m_slider->value() > 0) m_slider->setValue(m_slider->value() - 1);
    });
    connect(m_nextBtn, &QPushButton::clicked, this, [this]() {
        if (m_slider->value() < m_slider->maximum()) m_slider->setValue(m_slider->value() + 1);
    });

    connect(m_pinBtn, &QPushButton::clicked, this, [this]() { emit pinToggled(); });
    connect(m_prevPinBtn, &QPushButton::clicked, this, [this]() { emit jumpToPinRequested(false); });
    connect(m_nextPinBtn, &QPushButton::clicked, this, [this]() { emit jumpToPinRequested(true); });

    connect(m_exportBtn, &QPushButton::clicked, this, [this]() { emit exportRequested(); });
    connect(m_importBtn, &QPushButton::clicked, this, [this]() { emit importRequested(); });

    connect(m_searchField, &QLineEdit::returnPressed, this, &TimeMachineHUDWidget::onSearchReturnPressed);

    connect(m_diffBtn, &QPushButton::toggled, this, [this](bool checked) {
        m_isDiffActive = checked;
        emit diffToggled(checked);
    });

    connect(m_liveBtn, &QPushButton::clicked, this, [this]() { emit returnToLiveRequested(); });
}

void TimeMachineHUDWidget::onSliderValueChanged(int value) {
    emit snapshotSelected(value);
}

void TimeMachineHUDWidget::onSearchReturnPressed() {
    bool shiftPressed = QGuiApplication::keyboardModifiers().testFlag(Qt::ShiftModifier);
    emit searchRequested(m_searchField->text().trimmed(), !shiftPressed);
}

void TimeMachineHUDWidget::updateHUD(int count, int currentIndex, qint64 timestamp, bool isDiffActive) {
    if (count <= 0) return;

    m_slider->blockSignals(true);
    m_slider->setMaximum(count - 1);
    m_slider->setValue(currentIndex);
    m_slider->blockSignals(false);

    QString timeStr = QDateTime::fromMSecsSinceEpoch(timestamp * 1000).toString("HH:mm:ss");
    int baselineIdx = TimeMachineManager::instance().baselinePinIndex();

    if (isDiffActive) {
        if (baselineIdx >= 0) {
            m_infoLabel->setText(QString("%1 (DIFF #%2 vs PIN #%3)").arg(timeStr).arg(currentIndex + 1).arg(baselineIdx + 1));
        } else if (currentIndex > 0) {
            m_infoLabel->setText(QString("%1 (DIFF #%2 vs #%3)").arg(timeStr).arg(currentIndex + 1).arg(currentIndex));
        }
        m_infoLabel->setStyleSheet("color: #f39c12; font-weight: bold;");
    } else {
        m_infoLabel->setText(QString("%1 (#%2/%3)").arg(timeStr).arg(currentIndex + 1).arg(count));
        m_infoLabel->setStyleSheet("color: #ffffff;");
    }

    bool isPinned = TimeMachineManager::instance().isPinnedAtIndex(currentIndex);
    m_pinBtn->blockSignals(true);
    m_pinBtn->setChecked(isPinned);
    m_pinBtn->setText(isPinned ? "PINNED" : "PIN");
    m_pinBtn->blockSignals(false);

    adjustSize();
}