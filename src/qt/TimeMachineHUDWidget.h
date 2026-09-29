#pragma once

#include <QWidget>
#include <QPushButton>
#include <QSlider>
#include <QLabel>
#include <QLineEdit>

class TimeMachineHUDWidget : public QWidget {
    Q_OBJECT

public:
    explicit TimeMachineHUDWidget(QWidget *parent = nullptr);

    void updateHUD(int count, int currentIndex, qint64 timestamp, bool isDiffActive);

signals:
    void snapshotSelected(int index);
    void diffToggled(bool enabled);
    void returnToLiveRequested();
    void searchRequested(const QString &query, bool backward);
    void pinToggled();
    void jumpToPinRequested(bool forward);
    void exportRequested();
    void importRequested();

private slots:
    void onSliderValueChanged(int value);
    void onSearchReturnPressed();

private:
    void setupUi();

    QPushButton *m_prevBtn;
    QPushButton *m_nextBtn;
    QSlider *m_slider;
    QLabel *m_infoLabel;

    QPushButton *m_prevPinBtn;
    QPushButton *m_pinBtn;
    QPushButton *m_nextPinBtn;

    QPushButton *m_exportBtn;
    QPushButton *m_importBtn;
    QLineEdit *m_searchField;
    QPushButton *m_diffBtn;
    QPushButton *m_liveBtn;

    bool m_isDiffActive{false};
};