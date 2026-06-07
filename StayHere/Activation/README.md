# Activation module

Phase 2 implementation includes:
- Dock click interception (`DockClickInterceptor`)
- Interception enabled/disabled setting (`SettingsRepository.activationDockClickInterceptionEnabled`)
- Activation decisions (`ActivationPolicy`, including Option-gated single-window handling)
- Action execution (`ActivationExecutor`)
- App window summarization (`WindowIndex`)
