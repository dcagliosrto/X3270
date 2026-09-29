#include "TerminalWidget.h"
#include <QFontDatabase>
#include <QPaintEvent>
#include <QCoreApplication>
#include <QFile>
#include <QDir>
#include <QSettings>
#include <algorithm>
#include <utility>

TerminalWidget::TerminalWidget(QWidget *parent)
    : QWidget(parent) {
    
    setFocusPolicy(Qt::StrongFocus);

    QPalette pal = palette();
    pal.setColor(QPalette::Window, Qt::black);
    setAutoFillBackground(true);
    setPalette(pal);

    load3270Font();

    m_refreshTimer = new QTimer(this);
    connect(m_refreshTimer, &QTimer::timeout, this, [this]() {
        if (m_screen) update();
    });
    m_refreshTimer->start(33);
}

void TerminalWidget::load3270Font() {
    static QString loadedFamilyName;
    static bool fontAttempted = false;

    if (!fontAttempted) {
        fontAttempted = true;
        QStringList searchPaths = {
            QCoreApplication::applicationDirPath() + "/../Resources/fonts/3270-Regular.otf",
            QCoreApplication::applicationDirPath() + "/fonts/3270-Regular.otf",
            QCoreApplication::applicationDirPath() + "/3270-Regular.otf",
            "./fonts/3270-Regular.otf"
        };

        for (const QString &path : searchPaths) {
            if (QFile::exists(path)) {
                int id = QFontDatabase::addApplicationFont(path);
                if (id != -1) {
                    QStringList families = QFontDatabase::applicationFontFamilies(id);
                    if (!families.isEmpty()) {
                        loadedFamilyName = families.first();
                        break;
                    }
                }
            }
        }
    }

    if (!loadedFamilyName.isEmpty()) {
        m_font = QFont(loadedFamilyName, 15);
    } else {
        m_font = QFont("Menlo", 14);
        if (!m_font.exactMatch()) {
            m_font = QFont("Courier New", 14);
        }
    }

    m_font.setStyleHint(QFont::Monospace);
    m_font.setFixedPitch(true);
    m_font.setStyleStrategy(QFont::PreferAntialias);

    QFontMetrics metrics(m_font);
    m_charWidth = metrics.horizontalAdvance('M');
    if (m_charWidth <= 0) m_charWidth = 10;

    m_charHeight = metrics.height() + 1;
    if (m_charHeight <= 1) m_charHeight = 20;
    m_baseline = metrics.ascent();
}

void TerminalWidget::setScreenBuffer(x3270::ScreenBuffer* screen, x3270::EbcdicCodec* codec, x3270::KeyboardState* kbd) {
    m_screen = screen;
    m_codec = codec;
    m_kbd = kbd;
    update();
}

QSize TerminalWidget::sizeHint() const {
    int cols = (m_screen && m_screen->cols() > 0) ? m_screen->cols() : 80;
    int rows = (m_screen && m_screen->rows() > 0) ? m_screen->rows() : 24;
    return QSize(cols * m_charWidth, (rows + kOIARows) * m_charHeight);
}

void TerminalWidget::toggleRuler() {
    m_showRuler = !m_showRuler;
    update();
}

void TerminalWidget::executeISPFCommand(const QString &command) {
    if (command.isEmpty() || !m_kbd || !m_screen || !m_codec) return;

    QString finalCommand = command.trimmed();

    QSettings settings("DX3270", "CrossPlatform");
    QVariantList fastPaths = settings.value("FastPaths").toList();
    for (const QVariant &var : fastPaths) {
        QVariantMap map = var.toMap();
        QString shortcut = map["cmd"].toString();
        if (shortcut.startsWith("=") && finalCommand == shortcut.mid(1)) {
            finalCommand = shortcut;
            break;
        }
    }

    QStringList tsoCommands = {"TIME", "LISTALC", "LISTDS", "STATUS", "ALLOC", "FREE", "SUBMIT"};
    QString upper = finalCommand.toUpper();
    for (const QString &tso : tsoCommands) {
        if (upper == tso || upper.startsWith(tso + " ")) {
            if (!upper.startsWith("TSO ") && !upper.startsWith("=")) {
                finalCommand = "TSO " + finalCommand;
            }
            break;
        }
    }

    int position = -1;
    int size = m_screen->size();
    uint8_t equals = m_codec->fromAscii('=');
    uint8_t greater = m_codec->fromAscii('>');

    for (int index = 0; index < size - 4; index++) {
        if (m_screen->at(index).ch == equals &&
            m_screen->at(index + 1).ch == equals &&
            m_screen->at(index + 2).ch == equals &&
            m_screen->at(index + 3).ch == greater) {
            position = index + 4;
            if (position < size && m_screen->at(position).isFA) position++;
            break;
        }
    }

    if (position >= 0) {
        m_screen->setCursor(position);
    } else {
        m_kbd->handleHome();
    }

    m_kbd->handleEraseEOF();
    std::string asciiCmd = finalCommand.toStdString();
    for (char ch : asciiCmd) {
        m_kbd->handleChar(static_cast<uint16_t>(ch));
    }
    m_kbd->handleEnter();
    update();
}

QColor TerminalWidget::getCellColor(bool isProtected, bool isIntensified) {
    if (isProtected) return isIntensified ? QColor(217, 217, 217) : QColor(56, 133, 255);
    return isIntensified ? Qt::red : QColor(51, 217, 51);
}

QColor TerminalWidget::colorFor3270Code(uint8_t code) {
    switch (code) {
        case 0xF1: return QColor(56, 133, 255);
        case 0xF2: return QColor(255, 84, 84);
        case 0xF3: return QColor(255, 112, 255);
        case 0xF4: return QColor(51, 217, 51);
        case 0xF5: return QColor(51, 217, 217);
        case 0xF6: return QColor(217, 217, 51);
        case 0xF7: return QColor(217, 217, 217);
        default:   return QColor();
    }
}

void TerminalWidget::paintEvent(QPaintEvent *event) {
    Q_UNUSED(event);

    if (m_isTimeMachineActive) {
        const ScreenSnapshot *snap = TimeMachineManager::instance().snapshotAt(m_currentTimeMachineIndex);
        if (!snap) return;

        QPainter painter(this);
        painter.setRenderHint(QPainter::TextAntialiasing, true);
        painter.setFont(m_font);

        int cols = snap->cols;
        int rows = snap->rows;
        qreal scaleX = static_cast<qreal>(width()) / (cols * m_charWidth);
        qreal scaleY = static_cast<qreal>(height()) / ((rows + kOIARows) * m_charHeight);

        painter.save();
        painter.scale(scaleX, scaleY);

        const ushort *chars = reinterpret_cast<const ushort*>(snap->characterBuffer.constData());
        QList<int> diffMap;

        if (m_isDiffActive) {
            int baseIdx = TimeMachineManager::instance().baselinePinIndex();
            const ScreenSnapshot *baseSnap = (baseIdx >= 0) ? TimeMachineManager::instance().snapshotAt(baseIdx)
                                                             : TimeMachineManager::instance().snapshotAt(m_currentTimeMachineIndex - 1);
            if (baseSnap) {
                diffMap = TimeMachineManager::instance().compareSnapshots(*snap, *baseSnap);
            }
        }

        for (int r = 0; r < rows; ++r) {
            for (int c = 0; c < cols; ++c) {
                int pos = r * cols + c;
                ushort uc = chars[pos];
                int x = c * m_charWidth;
                int y = r * m_charHeight;

                bool isModified = (!diffMap.isEmpty() && diffMap[pos] == CellDiffModified);
                QColor bg = isModified ? QColor(115, 51, 0, 200) : Qt::black;
                QColor fg = isModified ? QColor(255, 235, 80) : QColor(51, 217, 51);

                if (bg != Qt::black) painter.fillRect(x, y, m_charWidth, m_charHeight, bg);
                if (uc > 0x20) {
                    painter.setPen(fg);
                    painter.drawText(x, y + m_baseline, QString(QChar(uc)));
                }
            }
        }
        drawOIA(painter, cols * m_charWidth, (rows + kOIARows) * m_charHeight);
        painter.restore();

        if (m_timeMachineHUD) m_timeMachineHUD->move((width() - m_timeMachineHUD->width()) / 2, height() - 50);
        return;
    }

    if (!m_screen || !m_codec) return;

    QPainter painter(this);
    painter.setRenderHint(QPainter::TextAntialiasing, true);
    painter.setFont(m_font);

    int cols = std::max(1, m_screen->cols());
    int rows = std::max(1, m_screen->rows());

    int prefWidth = cols * m_charWidth;
    int prefHeight = (rows + kOIARows) * m_charHeight;

    if (prefWidth <= 0 || prefHeight <= 0) return;

    qreal scaleX = static_cast<qreal>(width()) / prefWidth;
    qreal scaleY = static_cast<qreal>(height()) / prefHeight;

    painter.save();
    painter.scale(scaleX, scaleY);

    for (int r = 0; r < rows; ++r) {
        for (int c = 0; c < cols; ++c) {
            int pos = r * cols + c;
            if (pos >= m_screen->size()) continue;

            const auto& cell = m_screen->at(pos);
            if (cell.isNonDisplay() || cell.isFA) continue;

            int x = c * m_charWidth;
            int y = r * m_charHeight;

            QColor fgColor;
            QColor bgColor = Qt::black;

            if (cell.fgColor >= 0xF1 && cell.fgColor <= 0xF7) { 
                fgColor = colorFor3270Code(cell.fgColor);
            } else {
                int faIdx = m_screen->findFieldStart(pos);
                uint8_t activeAttr = (faIdx >= 0) ? m_screen->at(faIdx).attr : cell.attr;
                bool isProtected = (activeAttr & 0x20) != 0;
                bool isIntensified = (activeAttr & 0x08) != 0;
                fgColor = getCellColor(isProtected, isIntensified);
            }

            if (cell.highlight == 0xF2) std::swap(fgColor, bgColor);

            if (bgColor != Qt::black) {
                painter.fillRect(x, y, m_charWidth, m_charHeight, bgColor);
            }

            uint16_t uc = m_codec->toUnicode(cell.ch);
            if (uc >= 0x20) {
                painter.setPen(fgColor);
                painter.drawText(x, y + m_baseline, QString(QChar(uc)));
            }

            if (cell.highlight == 0xF4) {
                painter.setPen(fgColor);
                painter.drawLine(x, y + m_charHeight - 1, x + m_charWidth, y + m_charHeight - 1);
            }
        }
    }

    // Block Cursor
    int cursorPos = m_screen->cursorPos();
    int curR = cursorPos / cols;
    int curC = cursorPos % cols;
    painter.fillRect(curC * m_charWidth, curR * m_charHeight, m_charWidth, m_charHeight, QColor(51, 217, 51, 150));

    // Crosshair Ruler
    if (m_showRuler) {
        int lineX = curC * m_charWidth;
        int lineY = (curR + 1) * m_charHeight;
        int textAreaBottom = rows * m_charHeight;

        painter.setPen(QPen(QColor(255, 50, 50, 120), 2));
        painter.drawLine(0, lineY, cols * m_charWidth, lineY);
        painter.drawLine(lineX, 0, lineX, textAreaBottom);
    }

    drawOIA(painter, cols * m_charWidth, (rows + kOIARows) * m_charHeight);

    painter.restore();
}

void TerminalWidget::drawOIA(QPainter &painter, int effectiveWidth, int effectiveHeight) {
    Q_UNUSED(effectiveHeight);
    int rows = m_screen->rows();
    int oiaY = rows * m_charHeight;

    painter.setPen(QColor(100, 100, 100));
    painter.drawLine(0, oiaY, effectiveWidth, oiaY);

    painter.setPen(QColor(150, 150, 150));
    int textY = oiaY + m_baseline + 2;

    QString statusStr = "";
    if (m_kbd) {
        switch (m_kbd->lockReason()) {
            case x3270::KeyboardState::LockReason::None:        statusStr = ""; break;
            case x3270::KeyboardState::LockReason::Connecting:  statusStr = "Connecting..."; break;
            case x3270::KeyboardState::LockReason::System:      statusStr = "X SYS"; break;
            case x3270::KeyboardState::LockReason::OErr:        statusStr = "X OERR"; break;
        }
        if (m_kbd->isInsertMode()) statusStr += " ^";
    }
    painter.drawText(4, textY, statusStr);

    QString versionStr = "DX3270 v1.7.6 build 1 — © 2026 Swen Skalski";
    QFont dimFont = m_font;
    dimFont.setPointSize(std::max(8, m_font.pointSize() - 2));
    painter.setFont(dimFont);
    painter.setPen(QColor(80, 80, 80));
    
    int vWidth = painter.fontMetrics().horizontalAdvance(versionStr);
    int vX = (effectiveWidth - vWidth) / 2;
    painter.drawText(vX, oiaY + m_charHeight + m_baseline, versionStr);

    painter.setFont(m_font);
    painter.setPen(QColor(150, 150, 150));

    int pos = m_screen->cursorPos();
    int cols = m_screen->cols();
    QString cursorInfo = QString("%1/%2")
                            .arg(pos / cols + 1, 3, 10, QChar('0'))
                            .arg(pos % cols + 1, 3, 10, QChar('0'));
    
    int textWidth = painter.fontMetrics().horizontalAdvance(cursorInfo);
    painter.drawText(effectiveWidth - textWidth - 8, textY, cursorInfo);
}

void TerminalWidget::captureCurrentScreenSnapshot() {
    if (m_isTimeMachineActive || !m_screen || !m_codec) return;

    int rows = m_screen->rows();
    int cols = m_screen->cols();
    if (rows <= 0 || cols <= 0) return;

    QList<ushort> chars(rows * cols, ' ');
    QList<uint32_t> attrs(rows * cols, 0);

    for (int r = 0; r < rows; ++r) {
        for (int c = 0; c < cols; ++c) {
            int pos = r * cols + c;
            const auto &cell = m_screen->at(pos);
            uint16_t uc = m_codec->toUnicode(cell.ch);
            chars[pos] = (uc >= 0x20) ? uc : ' ';

            uint8_t colorVal = cell.fgColor;
            uint8_t colorType = (colorVal != 0x00) ? 1 : 2;
            attrs[pos] = (static_cast<uint32_t>(colorType) << 16) | (static_cast<uint32_t>(colorVal) << 8) | cell.attr;
        }
    }

    int curPos = m_screen->cursorPos();
    TimeMachineManager::instance().captureSnapshot(rows, cols, chars.constData(), attrs.constData(), curPos / cols, curPos % cols);
}

void TerminalWidget::toggleTimeMachine() {
    if (m_isTimeMachineActive) {
        onTimeMachineReturnToLive();
    } else {
        int count = TimeMachineManager::instance().snapshotCount();
        if (count == 0) return;

        m_isTimeMachineActive = true;
        m_currentTimeMachineIndex = count - 1;

        if (!m_timeMachineHUD) {
            m_timeMachineHUD = new TimeMachineHUDWidget(this);
            connect(m_timeMachineHUD, &TimeMachineHUDWidget::snapshotSelected, this, &TerminalWidget::onTimeMachineSnapshotSelected);
            connect(m_timeMachineHUD, &TimeMachineHUDWidget::diffToggled, this, &TerminalWidget::onTimeMachineDiffToggled);
            connect(m_timeMachineHUD, &TimeMachineHUDWidget::returnToLiveRequested, this, &TerminalWidget::onTimeMachineReturnToLive);
            connect(m_timeMachineHUD, &TimeMachineHUDWidget::searchRequested, this, &TerminalWidget::onTimeMachineSearchRequested);
            connect(m_timeMachineHUD, &TimeMachineHUDWidget::pinToggled, this, [this]() {
                TimeMachineManager::instance().togglePinAtIndex(m_currentTimeMachineIndex);
                const auto *snap = TimeMachineManager::instance().snapshotAt(m_currentTimeMachineIndex);
                if (snap) m_timeMachineHUD->updateHUD(TimeMachineManager::instance().snapshotCount(), m_currentTimeMachineIndex, snap->timestamp, m_isDiffActive);
            });
            connect(m_timeMachineHUD, &TimeMachineHUDWidget::jumpToPinRequested, this, [this](bool forward) {
                int target = forward ? TimeMachineManager::instance().nextPinnedIndexAfter(m_currentTimeMachineIndex)
                                     : TimeMachineManager::instance().prevPinnedIndexBefore(m_currentTimeMachineIndex);
                if (target != -1) onTimeMachineSnapshotSelected(target);
            });
        }

        m_timeMachineHUD->move((width() - m_timeMachineHUD->width()) / 2, height() - 55);
        m_timeMachineHUD->show();
        m_timeMachineHUD->raise();

        const auto *snap = TimeMachineManager::instance().snapshotAt(m_currentTimeMachineIndex);
        if (snap) m_timeMachineHUD->updateHUD(count, m_currentTimeMachineIndex, snap->timestamp, m_isDiffActive);
        update();
    }
}

void TerminalWidget::onTimeMachineSnapshotSelected(int index) {
    m_currentTimeMachineIndex = index;
    const auto *snap = TimeMachineManager::instance().snapshotAt(index);
    if (snap && m_timeMachineHUD) {
        m_timeMachineHUD->updateHUD(TimeMachineManager::instance().snapshotCount(), index, snap->timestamp, m_isDiffActive);
    }
    update();
}

void TerminalWidget::onTimeMachineDiffToggled(bool enabled) {
    m_isDiffActive = enabled;
    if (enabled && TimeMachineManager::instance().isPinnedAtIndex(m_currentTimeMachineIndex)) {
        TimeMachineManager::instance().setBaselinePinIndex(m_currentTimeMachineIndex);
    } else if (!enabled) {
        TimeMachineManager::instance().setBaselinePinIndex(-1);
    }
    onTimeMachineSnapshotSelected(m_currentTimeMachineIndex);
}

void TerminalWidget::onTimeMachineReturnToLive() {
    m_isTimeMachineActive = false;
    m_isDiffActive = false;
    if (m_timeMachineHUD) m_timeMachineHUD->hide();
    update();
}

void TerminalWidget::onTimeMachineSearchRequested(const QString &query, bool backward) {
    int result = TimeMachineManager::instance().searchHistory(query, m_currentTimeMachineIndex, backward);
    if (result != -1) {
        onTimeMachineSnapshotSelected(result);
    }
}

void TerminalWidget::keyPressEvent(QKeyEvent *event) {
    int key = event->key();
    Qt::KeyboardModifiers mods = event->modifiers();

    // Cmd+Option+T -> Toggle Time-Machine
    if ((mods & Qt::ControlModifier || mods & Qt::AltModifier) && key == Qt::Key_T) {
        toggleTimeMachine();
        return;
    }

    if (!m_kbd) {
        QWidget::keyPressEvent(event);
        return;
    }

    bool handled = false;

    if (key == Qt::Key_Return || key == Qt::Key_Enter) {
        handled = m_kbd->handleEnter();
    } else if (key == Qt::Key_Tab) {
        handled = m_kbd->handleTab((mods & Qt::ShiftModifier) != 0);
    } else if (key == Qt::Key_Backspace) {
        handled = m_kbd->handleBackspace();
    } else if (key == Qt::Key_Delete) {
        handled = m_kbd->handleDelete();
    } else if (key == Qt::Key_Home) {
        handled = m_kbd->handleHome();
    } else if (key == Qt::Key_Up) {
        handled = m_kbd->handleCursorUp();
    } else if (key == Qt::Key_Down) {
        handled = m_kbd->handleCursorDown();
    } else if (key == Qt::Key_Left) {
        handled = m_kbd->handleCursorLeft();
    } else if (key == Qt::Key_Right) {
        handled = m_kbd->handleCursorRight();
    } else if (key >= Qt::Key_F1 && key <= Qt::Key_F12) {
        int pfNum = key - Qt::Key_F1 + 1;
        if (mods & Qt::ShiftModifier) pfNum += 12;
        handled = m_kbd->handlePF(pfNum);
    } else if (!event->text().isEmpty()) {
        QChar c = event->text().at(0);
        if (c.unicode() >= 0x20 && c.unicode() != 0x7F) {
            handled = m_kbd->handleChar(c.unicode());
        }
    }

    if (handled) {
        update();
    } else {
        QWidget::keyPressEvent(event);
    }
}