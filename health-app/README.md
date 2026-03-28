# VitalSync - AI-Powered Health Monitoring App

A professional Flutter mobile application for real-time health monitoring with AI-based risk categorization and personalized health recommendations.

## Features

### Core Functionality
- **Real-time Vital Monitoring**: Track heart rate, SpO2, blood pressure, and temperature with live status indicators
- **AI-Powered Risk Analysis**: Intelligent risk categorization based on vital readings and health patterns
- **Personalized Recommendations**: AI-generated action plans with prioritized tasks and health impact projections
- **Health Analytics**: Comprehensive metrics tracking with trend analysis over different time periods
- **Smart Alerts**: Configurable alerts and thresholds for critical health events
- **Device Management**: Support for multiple wearable device connections (HealthWatch Pro, Oura Ring, etc.)

### User Experience
- **Intuitive Onboarding**: 3-step profile setup to personalize health insights
- **Beautiful Dashboard**: Clean, modern interface displaying health status at a glance
- **Comprehensive Settings**: Detailed profile management, device pairing, alert configuration
- **Data Privacy**: Secure data handling with privacy controls and data export options

## Project Structure

```
lib/
├── main.dart                      # App entry point and routing
├── config/
│   └── app_theme.dart            # Theme configuration and design system
├── models/
│   ├── user_model.dart           # User profile and settings
│   ├── vitals_model.dart         # Vital readings and vital statuses
│   ├── analysis_model.dart       # Health analysis and alerts
│   └── recommendation_model.dart # AI recommendations and tasks
├── providers/
│   ├── auth_provider.dart        # Authentication state management
│   └── health_provider.dart      # Health data state management
├── services/
│   └── mock_health_service.dart  # Mock data generation service
└── screens/
    ├── auth/
    │   ├── welcome_screen.dart       # Splash/welcome screen
    │   ├── signin_screen.dart        # Sign in/up
    │   └── onboarding_screen.dart    # 3-step profile setup
    ├── dashboard/
    │   ├── dashboard_screen.dart     # Main dashboard with vitals
    │   └── widgets/
    │       ├── vital_card.dart       # Individual vital display
    │       ├── risk_status_card.dart # Risk overview card
    │       ├── quick_actions.dart    # Quick action buttons
    │       └── recent_alerts.dart    # Alert list widget
    ├── metrics/
    │   └── metrics_screen.dart       # Detailed metrics with charts
    ├── analysis/
    │   └── analysis_screen.dart      # AI analysis and insights
    ├── recommendations/
    │   └── recommendations_screen.dart # Action plans and tasks
    └── settings/
        └── settings_screen.dart      # User settings and preferences
```

## Getting Started

### Prerequisites
- Flutter SDK (3.0+)
- Dart SDK (3.0+)
- Android Studio / Xcode (for running on emulator/device)

### Installation

1. **Clone the repository**
```bash
git clone <repository-url>
cd health_monitor_ai
```

2. **Install dependencies**
```bash
flutter pub get
```

3. **Run the app**
```bash
flutter run
```

## Architecture

### State Management
The app uses **Provider** for state management with two main providers:

- **AuthProvider**: Handles user authentication and profile management
- **HealthProvider**: Manages health data, vitals, analysis, and recommendations

### Data Models
- **User**: Profile information (age, weight, height, activity level, conditions, medications)
- **VitalReading**: Single vital sign measurement with status determination
- **HealthAnalysis**: AI-generated analysis with risk scores and contributing factors
- **RecommendedTask**: Individual health recommendation with priority and status tracking
- **HealthImpactProjection**: Expected health improvements from following recommendations

### Mock Data Service
The `MockHealthService` generates realistic health data for:
- Individual vital readings with circadian rhythm simulation
- 30-day vital history for trend analysis
- AI-powered risk analysis based on vital patterns
- Personalized health recommendations
- Device and alert threshold configurations

## Design System

### Color Palette
- **Primary**: #4F46E5 (Indigo) - Brand color
- **Success**: #10B981 (Green) - Normal/healthy status
- **Warning**: #F59E0B (Orange) - Elevated/warning status
- **Danger**: #EF4444 (Red) - Critical/alert status
- **Neutral**: #1F2937-#F3F4F6 (Dark to light grays)

### Typography
- **Font**: Poppins (heading and body)
- **Sizes**: Semantic scaling from 12px to 32px
- **Line Height**: 1.4-1.6 for optimal readability

### Components
- **Cards**: Rounded corners (12px) with subtle borders
- **Buttons**: Elevated and outlined variants
- **Input Fields**: Rounded (12px) with focus states
- **Progress Indicators**: Linear and circular variants

## Key Features Explained

### Vital Status System
Each vital sign has a status based on health guidelines:
- **Normal**: Safe range (green)
- **Elevated**: Slightly outside normal (orange)
- **Critical**: Dangerous levels (red)

### Risk Scoring
Overall health risk is calculated using:
- Individual vital readings
- Heart rate variability (HRV) trends
- Sleep quality patterns
- User's health context (conditions, medications, activity level)

### AI Recommendations
The system generates personalized action plans with:
- **Prioritized Tasks**: High/Medium/Low priority based on impact
- **Daily Goals**: Specific metrics and targets
- **Impact Projections**: Expected health improvements
- **Medical Disclaimers**: Important safety information

### Device Management
Supports multiple wearable devices with:
- Connection status tracking
- Battery monitoring
- Last sync timestamps
- Manual pairing interface

## Mock Data Generation

The app includes comprehensive mock data generation:

```dart
// Generate a realistic vital reading
VitalReading reading = MockHealthService.generateMockVitalReading(
  userId: 'user123'
);

// Generate 30-day history
List<VitalReading> history = MockHealthService.generateMockVitalsHistory(
  userId: 'user123',
  days: 30,
);

// Generate AI analysis
HealthAnalysis analysis = MockHealthService.generateMockAnalysis(
  userId: 'user123',
  recentReadings: history.take(24).toList(),
);

// Generate recommendations
HealthRecommendation rec = MockHealthService.generateMockRecommendations(
  userId: 'user123',
  analysis: analysis,
);
```

## Integration Points

The app is designed to easily integrate with:

### Real Health Data Sources
- HealthKit (iOS)
- Google Fit (Android)
- Bluetooth wearable devices
- REST APIs for device synchronization

### AI & Analytics Services
- Custom ML models for risk assessment
- Natural Language Processing for recommendations
- Cloud services for data synchronization
- Analytics platforms for usage tracking

### Backend Integration
Replace mock services with real API calls:
```dart
// In health_provider.dart
Future<void> initializeHealth(String userId) async {
  // Replace mock data generation with API calls
  _currentVitals = await apiClient.getLatestVitals(userId);
  _currentAnalysis = await apiClient.getHealthAnalysis(userId);
  // ... etc
}
```

## Testing

### Current State
The app uses mock data for complete functionality demonstration without a backend.

### Adding Real Data
To integrate real health data:
1. Update `services/mock_health_service.dart` with API client calls
2. Implement proper error handling and retry logic
3. Add caching strategies for offline support
4. Implement data synchronization with backend

## Performance Optimizations

- **Provider**: Efficient state management with selective rebuilds
- **Lazy Loading**: Data fetched on demand
- **Pagination**: Large lists load in chunks
- **Caching**: Vitals and analysis cached locally
- **Responsive Design**: Optimized for various screen sizes

## Security Considerations

- **Data Privacy**: All health data should be encrypted in transit and at rest
- **Authentication**: Implement secure token management
- **Biometric Auth**: Optional biometric login (fingerprint/face)
- **Data Permissions**: Explicit user consent for data collection
- **HIPAA Compliance**: Follow health data protection standards

## Browser Requirements

When deploying to web:
- Modern browsers (Chrome 90+, Firefox 88+, Safari 14+)
- HTTPS required for camera/sensor access
- Responsive design for mobile browsers

## Future Enhancements

- [ ] Real wearable device integration
- [ ] Custom ML model deployment
- [ ] Backend API integration
- [ ] Social sharing and community features
- [ ] Telemedicine consultations
- [ ] Advanced analytics dashboard
- [ ] Export to PDF/CSV
- [ ] Push notifications
- [ ] Offline data sync
- [ ] Multi-language support

## Troubleshooting

### App crashes on startup
- Ensure all dependencies are installed: `flutter pub get`
- Check Dart SDK version compatibility
- Clear build cache: `flutter clean && flutter pub get`

### Provider errors
- Ensure providers are properly wrapped in MultiProvider
- Check provider initialization in main.dart

### Mock data not loading
- Verify MockHealthService is imported correctly
- Check HealthProvider initialization in dashboard_screen

## License

This project is licensed under the MIT License - see LICENSE file for details.

## Support

For issues, feature requests, or contributions:
1. Open an issue on GitHub
2. Submit a pull request with improvements
3. Contact: support@vitalsync.com

## Author

VitalSync Development Team
Built with Flutter & ❤️

---

**Note**: This is a demo application with mock data. For production use, integrate with real health data sources and implement proper backend services.
