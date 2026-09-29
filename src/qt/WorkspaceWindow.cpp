#include "WorkspaceWindow.h"
#include <QVBoxLayout>

WorkspaceWindow::WorkspaceWindow(QWidget *parent)
    : QMainWindow(parent) {

    setWindowTitle("DX3270 Workspace");
    resize(1200, 800);
    setMinimumSize(800, 500);

    WorkspaceManager::instance().loadWorkspaces();
    setupUi();

    if (!WorkspaceManager::instance().workspaces().isEmpty()) {
        m_sidebar->setWorkspace(&WorkspaceManager::instance().workspaces().first());
    }
}

void WorkspaceWindow::setupUi() {
    m_mainSplitter = new QSplitter(Qt::Horizontal, this);
    m_mainSplitter->setHandleWidth(1);
    m_mainSplitter->setStyleSheet("QSplitter::handle { background-color: #333333; }");

    m_sidebar = new WorkspaceSidebarWidget(m_mainSplitter);
    m_sidebar->setMinimumWidth(220);
    m_sidebar->setMaximumWidth(350);

    m_paneContainer = new QWidget(m_mainSplitter);
    m_paneContainer->setStyleSheet("background-color: #101010;");

    QVBoxLayout *containerLayout = new QVBoxLayout(m_paneContainer);
    containerLayout->setContentsMargins(0, 0, 0, 0);

    m_emptyLabel = new QLabel("Nessuna sessione attiva\nFai doppio clic su un sistema nella barra laterale per connetterti", m_paneContainer);
    m_emptyLabel->setAlignment(Qt::AlignCenter);
    m_emptyLabel->setStyleSheet("color: #666666; font-size: 13px; font-weight: 500;");
    containerLayout->addWidget(m_emptyLabel);

    m_transferDockPlaceholder = new QWidget(m_mainSplitter);
    m_transferDockPlaceholder->setMinimumWidth(250);
    m_transferDockPlaceholder->hide();

    m_mainSplitter->addWidget(m_sidebar);
    m_mainSplitter->addWidget(m_paneContainer);
    m_mainSplitter->addWidget(m_transferDockPlaceholder);

    m_mainSplitter->setStretchFactor(0, 0);
    m_mainSplitter->setStretchFactor(1, 1);
    m_mainSplitter->setStretchFactor(2, 0);

    setCentralWidget(m_mainSplitter);

    connect(m_sidebar, &WorkspaceSidebarWidget::sessionDoubleClicked, this, &WorkspaceWindow::onSessionDoubleClicked);
}

void WorkspaceWindow::onSessionDoubleClicked(const DXSessionConfig &config) {
    ConnectionSettings settings;
    settings.host = config.host;
    settings.port = config.port;
    settings.useSSL = config.useSSL;
    settings.verifyCert = config.verifyCert;
    settings.protocol = config.protocol;
    settings.model = config.model;
    settings.codePage = config.codePage;

    TerminalPaneWidget *newPane = new TerminalPaneWidget(settings, this);
    m_allPanes.append(newPane);

    connect(newPane, &TerminalPaneWidget::paneFocused, this, &WorkspaceWindow::onPaneFocused);
    connect(newPane, &TerminalPaneWidget::splitRequested, this, &WorkspaceWindow::onSplitRequested);
    connect(newPane, &TerminalPaneWidget::closeRequested, this, &WorkspaceWindow::onCloseRequested);

    if (m_allPanes.count() == 1) {
        setRootWidget(newPane);
    } else if (m_activePane) {
        replaceWidget(m_activePane, newPane);
        m_allPanes.removeOne(m_activePane);
        m_activePane->deleteLater();
    }

    setActivePane(newPane);
}

void WorkspaceWindow::onPaneFocused(TerminalPaneWidget *pane) {
    setActivePane(pane);
}

void WorkspaceWindow::onSplitRequested(TerminalPaneWidget *pane, Qt::Orientation orientation) {
    if (!pane) return;

    ConnectionSettings settings = pane->settings();
    TerminalPaneWidget *newPane = new TerminalPaneWidget(settings, this);
    m_allPanes.append(newPane);

    connect(newPane, &TerminalPaneWidget::paneFocused, this, &WorkspaceWindow::onPaneFocused);
    connect(newPane, &TerminalPaneWidget::splitRequested, this, &WorkspaceWindow::onSplitRequested);
    connect(newPane, &TerminalPaneWidget::closeRequested, this, &WorkspaceWindow::onCloseRequested);

    QSplitter *split = new QSplitter(orientation, this);
    split->setHandleWidth(2);
    split->setStyleSheet("QSplitter::handle { background-color: #007acc; }");

    replaceWidget(pane, split);

    split->addWidget(pane);
    split->addWidget(newPane);

    QList<int> sizes;
    sizes << split->width() / 2 << split->width() / 2;
    split->setSizes(sizes);

    setActivePane(newPane);
}

void WorkspaceWindow::onCloseRequested(TerminalPaneWidget *pane) {
    if (!pane) return;

    m_allPanes.removeOne(pane);

    QWidget *parent = pane->parentWidget();
    QSplitter *parentSplitter = qobject_cast<QSplitter*>(parent);

    pane->deleteLater();

    if (parentSplitter) {
        if (parentSplitter->count() == 1) {
            QWidget *remainingChild = parentSplitter->widget(0);
            replaceWidget(parentSplitter, remainingChild);
            parentSplitter->deleteLater();
        }
    }

    if (m_activePane == pane) {
        m_activePane = nullptr;
        if (!m_allPanes.isEmpty()) {
            setActivePane(m_allPanes.last());
        }
    }

    checkEmptyState();
}

void WorkspaceWindow::setActivePane(TerminalPaneWidget *pane) {
    for (auto *p : m_allPanes) {
        p->setActive(p == pane);
    }
    m_activePane = pane;

    if (m_activePane) {
        setWindowTitle(QString("DX3270 Workspace - %1").arg(m_activePane->settings().host));
    } else {
        setWindowTitle("DX3270 Workspace");
    }
}

void WorkspaceWindow::setRootWidget(QWidget *widget) {
    QVBoxLayout *layout = qobject_cast<QVBoxLayout*>(m_paneContainer->layout());
    if (!layout) return;

    m_emptyLabel->hide();
    layout->addWidget(widget);
}

void WorkspaceWindow::replaceWidget(QWidget *oldWidget, QWidget *newWidget) {
    QWidget *parent = oldWidget->parentWidget();
    QSplitter *splitter = qobject_cast<QSplitter*>(parent);

    if (splitter) {
        int index = splitter->indexOf(oldWidget);
        oldWidget->setParent(nullptr);
        splitter->insertWidget(index, newWidget);
    } else if (parent == m_paneContainer) {
        QVBoxLayout *layout = qobject_cast<QVBoxLayout*>(m_paneContainer->layout());
        if (layout) {
            layout->removeWidget(oldWidget);
            oldWidget->setParent(nullptr);
            layout->addWidget(newWidget);
        }
    }
}

void WorkspaceWindow::checkEmptyState() {
    if (m_allPanes.isEmpty()) {
        m_emptyLabel->show();
        setWindowTitle("DX3270 Workspace");
    }
}