// src/qt/WorkspaceWindow.h
#pragma once

#include <QMainWindow>
#include <QSplitter>
#include <QLabel>
#include <QList>
#include "WorkspaceSidebarWidget.h"
#include "TerminalPaneWidget.h"
#include "WorkspaceManager.h"

class WorkspaceWindow : public QMainWindow {
    Q_OBJECT

public:
    explicit WorkspaceWindow(QWidget *parent = nullptr);
    ~WorkspaceWindow() override = default;

private slots:
    void onSessionDoubleClicked(const DXSessionConfig &config);
    void onPaneFocused(TerminalPaneWidget *pane);
    void onSplitRequested(TerminalPaneWidget *pane, Qt::Orientation orientation);
    void onCloseRequested(TerminalPaneWidget *pane);

private:
    void setupUi();
    void setRootWidget(QWidget *widget);
    void replaceWidget(QWidget *oldWidget, QWidget *newWidget);
    void setActivePane(TerminalPaneWidget *pane);
    void checkEmptyState();

    QSplitter *m_mainSplitter{nullptr};
    WorkspaceSidebarWidget *m_sidebar{nullptr};
    QWidget *m_paneContainer{nullptr};
    QLabel *m_emptyLabel{nullptr};
    QWidget *m_transferDockPlaceholder{nullptr};

    QList<TerminalPaneWidget*> m_allPanes;
    TerminalPaneWidget *m_activePane{nullptr};
};