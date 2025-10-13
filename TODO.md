# JavIt Project TODO List

This document outlines potential improvements, new features, and optimizations for the JavIt Flutter desktop application based on a comprehensive code analysis.

## 🚀 New Features

- [ ] **Cross-Platform Support**: Extend build targets to Windows and Linux in addition to macOS. Update platform-specific logic in `app_setting.dart` and other files.
- [ ] **Advanced Search Filters**: Add filters for genre, studio, release year, quality, and subtitle language to enhance search capabilities in `page_search`.
- [ ] **Export Functionality**: Implement export options for video lists (CSV, JSON) to allow users to backup or share data.
- [ ] **Batch Operations**: Add support for bulk actions like marking favorites, deleting, or moving videos in the library.
- [ ] **User Collections**: Allow users to create custom collections or playlists beyond the existing favorites system.
- [ ] **Offline Mode Enhancements**: Improve offline capabilities, such as caching more metadata and handling network failures gracefully.
- [ ] **Notification System**: Expand notifications beyond download completion (e.g., new releases, reminders) using the existing audio notification setup.
- [ ] **Theme Customization**: Add light/dark mode toggle and custom theme options beyond the current dark theme.
- [ ] **Internationalization**: Expand language support using the existing i18n structure for more locales.
- [ ] **Analytics Dashboard**: Add a simple dashboard for viewing statistics (e.g., most watched, storage usage) in the tools or settings page.

## 🛠️ Performance Improvements

- [ ] **Database Optimization**: Review and optimize SQL queries in `db_videos.dart` and other database files for faster loading and searching.
- [ ] **Image Caching**: Enhance caching for thumbnails and posters using `cached_network_image` to reduce load times.
- [ ] **Video Playback Optimization**: Improve video player performance and add support for more formats using `cached_video_player_plus`.
- [ ] **Lazy Loading**: Implement lazy loading for large lists in home and search pages to improve UI responsiveness.
- [ ] **Memory Management**: Monitor and optimize memory usage in controllers like `home_controller.dart` to handle large libraries.

## 🎨 UI/UX Enhancements

- [ ] **Responsive Design**: Improve layout responsiveness for different window sizes and add mobile-like responsive features.
- [ ] **Accessibility**: Add accessibility features (e.g., screen reader support, keyboard navigation) for better usability.
- [ ] **Better Drag-and-Drop Feedback**: Enhance visual feedback during drag-and-drop operations in `home_view.dart`.
- [ ] **Side Menu Improvements**: Add animations and better organization to the side menu with sub-menus or categories.
- [ ] **Loading States**: Improve loading indicators and error states across all pages for a smoother user experience.
- [ ] **Fullscreen Mode Enhancements**: Better handling of fullscreen mode in player and main window.

## 🐛 Code Quality & Refactoring

- [ ] **Refactor Large Controllers**: Break down large controllers like `home_controller.dart` into smaller, more manageable pieces.
- [ ] **Error Handling**: Improve error handling in critical paths like database download, conversion, and file operations.
- [ ] **Code Documentation**: Add more comments and documentation to complex functions, especially in utilities and helpers.
- [ ] **Dependency Updates**: Update Flutter and packages in `pubspec.yaml` to latest versions for security and performance.
- [ ] **Remove Unused Code**: Audit and remove any unused dependencies, functions, or files to reduce app size.
- [ ] **Hotkey Expansion**: Add more hotkeys for common actions and make them customizable in settings.

## 🔒 Security & Privacy

- [ ] **API Security**: Ensure proxy APIs (e.g., javit-api.vercel.app) are secure and add fallback mechanisms.
- [ ] **Data Encryption**: Encrypt sensitive data in preferences and databases where appropriate.
- [ ] **Content Filtering**: Add options for content filtering or parental controls.

## 🧪 Testing & Debugging

- [ ] **Unit Tests**: Add comprehensive unit tests for models, utilities, and controllers using Flutter's testing framework.
- [ ] **Integration Tests**: Create integration tests for database operations and UI interactions.
- [ ] **Debug Logging**: Enhance logging in `app_logging.dart` for better debugging and production monitoring.
- [ ] **Performance Profiling**: Add tools for profiling and monitoring app performance.

## 📚 Documentation & Setup

- [ ] **Update README**: Enhance README.md with setup instructions, troubleshooting, and feature descriptions.
- [ ] **API Documentation**: Document external APIs and integration points.
- [ ] **User Guide**: Create a user guide or help section within the app.
- [ ] **Contributing Guidelines**: Add guidelines for contributing to the project.

## 🔧 Maintenance

- [ ] **Dependency Audit**: Regularly audit dependencies for vulnerabilities.
- [ ] **Build Scripts**: Improve build scripts and CI/CD for easier deployment.
- [ ] **Version Management**: Implement better version management and changelog.
- [ ] **Backup/Restore**: Add features for backing up and restoring user data and settings.

## Notes

- Prioritize items based on user feedback and project needs.
- Ensure all changes adhere to the project's coding rules and patterns, such as using `formatActressName()` for actress formatting and mandatory hotkey unregistration.
- Consider the adult content nature of the app when implementing features to maintain appropriate handling.