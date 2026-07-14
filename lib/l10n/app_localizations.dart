import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L10n
/// returned by `L10n.of(context)`.
///
/// Applications need to include `L10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L10n.localizationsDelegates,
///   supportedLocales: L10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L10n.supportedLocales
/// property.
abstract class L10n {
  L10n(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L10n of(BuildContext context) {
    return Localizations.of<L10n>(context, L10n)!;
  }

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru')
  ];

  /// Application name
  ///
  /// In en, this message translates to:
  /// **'Orpheus'**
  String get appName;

  /// Welcome screen subtitle
  ///
  /// In en, this message translates to:
  /// **'Secure communication without the noise'**
  String get welcomeSubtitle;

  /// Create account button
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get createAccount;

  /// Restore account button
  ///
  /// In en, this message translates to:
  /// **'Restore from Key'**
  String get restoreFromKey;

  /// E2E encryption label
  ///
  /// In en, this message translates to:
  /// **'End-to-end encryption'**
  String get e2eEncryption;

  /// Recovery dialog title
  ///
  /// In en, this message translates to:
  /// **'Recovery'**
  String get recovery;

  /// Recovery warning text
  ///
  /// In en, this message translates to:
  /// **'Private key grants full access to your account. Never share it with anyone.'**
  String get recoveryWarning;

  /// Private key input hint
  ///
  /// In en, this message translates to:
  /// **'Paste private key...'**
  String get pastePrivateKey;

  /// Cancel button
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Import button
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// Error prefix
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// Profile screen title
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// QR code section title
  ///
  /// In en, this message translates to:
  /// **'QR Code'**
  String get qrCode;

  /// Your ID section title
  ///
  /// In en, this message translates to:
  /// **'Your ID'**
  String get yourId;

  /// ID copied snackbar
  ///
  /// In en, this message translates to:
  /// **'ID copied'**
  String get idCopied;

  /// Share button
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// Share message template
  ///
  /// In en, this message translates to:
  /// **'Hi! Add me on Orpheus.\nMy key:\n{key}'**
  String shareMessage(String key);

  /// Contacts count label
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{contacts} =1{contact} other{contacts}}'**
  String contactsCount(int count);

  /// Messages count label
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{messages} =1{message} other{messages}}'**
  String messagesCount(int count);

  /// Sent count label
  ///
  /// In en, this message translates to:
  /// **'sent'**
  String get sentCount;

  /// Security menu item
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get security;

  /// Security menu description
  ///
  /// In en, this message translates to:
  /// **'PIN, duress, wipe'**
  String get securityDesc;

  /// Support menu item
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get support;

  /// Support menu description
  ///
  /// In en, this message translates to:
  /// **'Contact developer'**
  String get supportDesc;

  /// Help menu item
  ///
  /// In en, this message translates to:
  /// **'How to Use'**
  String get howToUse;

  /// Help menu description
  ///
  /// In en, this message translates to:
  /// **'Quick guide'**
  String get howToUseDesc;

  /// Updates menu item
  ///
  /// In en, this message translates to:
  /// **'Update History'**
  String get updateHistory;

  /// Update dialog title
  ///
  /// In en, this message translates to:
  /// **'Update Available'**
  String get updateAvailable;

  /// Update dialog message for required updates
  ///
  /// In en, this message translates to:
  /// **'New version {version} is available.\nThis is a critical security update.'**
  String updateMessageRequired(String version);

  /// Update dialog message for optional updates
  ///
  /// In en, this message translates to:
  /// **'New version {version} is available.\nWe recommend updating for stable operation.'**
  String updateMessageOptional(String version);

  /// Update dialog later button
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get updateLater;

  /// Update dialog download button
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get updateDownload;

  /// Update downloading progress dialog title
  ///
  /// In en, this message translates to:
  /// **'Downloading Update'**
  String get updateDownloading;

  /// Snackbar shown after download when the system install prompt appears
  ///
  /// In en, this message translates to:
  /// **'Confirm the installation in the system dialog'**
  String get updateConfirmInstall;

  /// Snackbar shown when no update is available
  ///
  /// In en, this message translates to:
  /// **'You have the latest version'**
  String get updateUpToDate;

  /// Update install error dialog title
  ///
  /// In en, this message translates to:
  /// **'Installation Error'**
  String get updateInstallError;

  /// Update install error dialog message
  ///
  /// In en, this message translates to:
  /// **'Could not install the update automatically. You can download it via browser.'**
  String get updateInstallErrorMessage;

  /// Open in browser button
  ///
  /// In en, this message translates to:
  /// **'Open in Browser'**
  String get updateOpenBrowser;

  /// Export menu item
  ///
  /// In en, this message translates to:
  /// **'Export Account'**
  String get exportAccount;

  /// Export menu description
  ///
  /// In en, this message translates to:
  /// **'Show private key'**
  String get exportAccountDesc;

  /// Notifications menu item
  ///
  /// In en, this message translates to:
  /// **'Notification Settings'**
  String get notificationSettings;

  /// Notifications menu description
  ///
  /// In en, this message translates to:
  /// **'For Android (Vivo, Xiaomi, etc.)'**
  String get notificationSettingsDesc;

  /// Orpheus notifications description
  ///
  /// In en, this message translates to:
  /// **'Notifications for messages in Orpheus public chat.'**
  String get orpheusNotificationsDesc;

  /// Toggle for official Orpheus notifications
  ///
  /// In en, this message translates to:
  /// **'Official Orpheus replies'**
  String get orpheusOfficialNotifications;

  /// Open system notification settings
  ///
  /// In en, this message translates to:
  /// **'System notification settings'**
  String get systemNotificationSettings;

  /// Language menu item
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// Language menu description
  ///
  /// In en, this message translates to:
  /// **'English, Русский'**
  String get languageDesc;

  /// Account creation date
  ///
  /// In en, this message translates to:
  /// **'Account created {date}'**
  String accountCreated(String date);

  /// Check updates button
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get checkUpdates;

  /// Delete account button
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccount;

  /// Delete account dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete Account?'**
  String get deleteAccountTitle;

  /// Delete account warning
  ///
  /// In en, this message translates to:
  /// **'This will delete keys, contacts and message history without possibility of recovery.'**
  String get deleteAccountWarning;

  /// Delete account confirmation checkbox
  ///
  /// In en, this message translates to:
  /// **'I understand this is irreversible'**
  String get deleteAccountConfirm;

  /// Delete button
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Delete for both option in chat
  ///
  /// In en, this message translates to:
  /// **'Delete for both'**
  String get deleteForBoth;

  /// Confirmation for delete for both
  ///
  /// In en, this message translates to:
  /// **'Delete for both? The message will also be removed on the recipient\'s device.'**
  String get deleteForBothConfirm;

  /// Number of selected messages
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String nSelected(int count);

  /// Confirm deletion of selected messages
  ///
  /// In en, this message translates to:
  /// **'Delete {count} messages?'**
  String deleteSelectedConfirm(int count);

  /// Select messages action
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get selectMessages;

  /// Private key dialog title
  ///
  /// In en, this message translates to:
  /// **'Private Key'**
  String get privateKey;

  /// Private key warning
  ///
  /// In en, this message translates to:
  /// **'Never share this key with anyone. Possession of it grants full access to your account.'**
  String get privateKeyWarning;

  /// Close button
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Copy button
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// Text copied to clipboard snackbar
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// Key copied snackbar
  ///
  /// In en, this message translates to:
  /// **'Key copied'**
  String get keyCopied;

  /// Biometry unavailable message
  ///
  /// In en, this message translates to:
  /// **'Biometry unavailable. Set up device security.'**
  String get biometryUnavailable;

  /// Biometry prompt
  ///
  /// In en, this message translates to:
  /// **'Confirm identity to export keys'**
  String get confirmIdentity;

  /// Auth error message
  ///
  /// In en, this message translates to:
  /// **'Authentication error'**
  String get authError;

  /// Account deleted message
  ///
  /// In en, this message translates to:
  /// **'Account deleted. Restart the app.'**
  String get accountDeleted;

  /// Online status
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get online;

  /// Offline status
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// Call button tooltip
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get call;

  /// Menu button tooltip
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get menu;

  /// Clear history dialog title
  ///
  /// In en, this message translates to:
  /// **'Clear History?'**
  String get clearHistory;

  /// Clear history warning
  ///
  /// In en, this message translates to:
  /// **'All messages with this contact will be permanently deleted.'**
  String get clearHistoryWarning;

  /// Empty chat title
  ///
  /// In en, this message translates to:
  /// **'Start a conversation'**
  String get startConversation;

  /// Empty chat subtitle
  ///
  /// In en, this message translates to:
  /// **'Messages are encrypted and stored locally.'**
  String get messagesEncrypted;

  /// Message input placeholder
  ///
  /// In en, this message translates to:
  /// **'Message...'**
  String get messagePlaceholder;

  /// Toggle to send messages as Orpheus
  ///
  /// In en, this message translates to:
  /// **'Write as Orpheus'**
  String get writeAsOrpheus;

  /// Today date label
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// Yesterday date label
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// Incoming call status
  ///
  /// In en, this message translates to:
  /// **'Incoming call'**
  String get incomingCall;

  /// Neutral incoming-call label shown on a locked device so the caller identity is not leaked on the lockscreen
  ///
  /// In en, this message translates to:
  /// **'Secure connection'**
  String get incomingEncryptedCall;

  /// Outgoing call status
  ///
  /// In en, this message translates to:
  /// **'Outgoing call'**
  String get outgoingCall;

  /// CallKit missed-call subtitle
  ///
  /// In en, this message translates to:
  /// **'Missed call'**
  String get missedCall;

  /// Call label
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get callLabel;

  /// Incoming direction
  ///
  /// In en, this message translates to:
  /// **'Incoming'**
  String get incoming;

  /// Outgoing direction
  ///
  /// In en, this message translates to:
  /// **'Outgoing'**
  String get outgoing;

  /// Chats tab
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chats;

  /// Contacts tab
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get contacts;

  /// Settings tab
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Orpheus public room name
  ///
  /// In en, this message translates to:
  /// **'Orpheus'**
  String get orpheusRoomName;

  /// Official badge label in Orpheus room
  ///
  /// In en, this message translates to:
  /// **'OFFICIAL'**
  String get orpheusOfficialBadge;

  /// Displayed name for Orpheus official messages
  ///
  /// In en, this message translates to:
  /// **'Orpheus'**
  String get orpheusOfficialName;

  /// Warning banner for Orpheus public room
  ///
  /// In en, this message translates to:
  /// **'Public chat. Do not share personal data.'**
  String get orpheusRoomWarning;

  /// Orpheus room unavailable message
  ///
  /// In en, this message translates to:
  /// **'Orpheus public chat is not available yet. Check the server or try again later.'**
  String get orpheusRoomUnavailable;

  /// Empty chats title
  ///
  /// In en, this message translates to:
  /// **'No chats yet'**
  String get noChats;

  /// Empty chats description
  ///
  /// In en, this message translates to:
  /// **'Add a contact to start messaging'**
  String get noChatsDesc;

  /// Add contact button
  ///
  /// In en, this message translates to:
  /// **'Add Contact'**
  String get addContact;

  /// Empty contacts title
  ///
  /// In en, this message translates to:
  /// **'No contacts'**
  String get noContacts;

  /// Empty contacts description
  ///
  /// In en, this message translates to:
  /// **'Scan QR code or paste contact\'s ID'**
  String get noContactsDesc;

  /// Scan QR button
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get scanQr;

  /// Add by ID button
  ///
  /// In en, this message translates to:
  /// **'Add by ID'**
  String get addById;

  /// New contact dialog title
  ///
  /// In en, this message translates to:
  /// **'New Contact'**
  String get newContact;

  /// Contact name field
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get contactName;

  /// Contact ID field
  ///
  /// In en, this message translates to:
  /// **'Contact ID'**
  String get contactId;

  /// Add button
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// Validation error when a required dialog field is empty
  ///
  /// In en, this message translates to:
  /// **'Please fill in both fields'**
  String get fillAllFields;

  /// Validation error when the pasted public key is not a valid key
  ///
  /// In en, this message translates to:
  /// **'Invalid key format'**
  String get invalidPublicKey;

  /// Contact added message
  ///
  /// In en, this message translates to:
  /// **'Contact added'**
  String get contactAdded;

  /// Contact exists error
  ///
  /// In en, this message translates to:
  /// **'Contact already exists'**
  String get contactExists;

  /// Invalid ID error
  ///
  /// In en, this message translates to:
  /// **'Invalid ID format'**
  String get invalidId;

  /// Cannot add self error
  ///
  /// In en, this message translates to:
  /// **'Cannot add yourself'**
  String get cannotAddSelf;

  /// Delete contact dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete Contact?'**
  String get deleteContact;

  /// Delete contact warning
  ///
  /// In en, this message translates to:
  /// **'Contact and chat history will be deleted.'**
  String get deleteContactWarning;

  /// Contact deleted message
  ///
  /// In en, this message translates to:
  /// **'Contact deleted'**
  String get contactDeleted;

  /// Rename contact dialog title
  ///
  /// In en, this message translates to:
  /// **'Rename Contact'**
  String get renameContact;

  /// Save button
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// PIN code title
  ///
  /// In en, this message translates to:
  /// **'PIN Code'**
  String get pinCode;

  /// Enter PIN prompt
  ///
  /// In en, this message translates to:
  /// **'Enter PIN'**
  String get enterPin;

  /// Confirm PIN prompt
  ///
  /// In en, this message translates to:
  /// **'Confirm PIN'**
  String get confirmPin;

  /// PIN mismatch error
  ///
  /// In en, this message translates to:
  /// **'PINs do not match'**
  String get pinMismatch;

  /// PIN set message
  ///
  /// In en, this message translates to:
  /// **'PIN set'**
  String get pinSet;

  /// PIN disabled message
  ///
  /// In en, this message translates to:
  /// **'PIN disabled'**
  String get pinDisabled;

  /// Wrong PIN error
  ///
  /// In en, this message translates to:
  /// **'Wrong PIN'**
  String get wrongPin;

  /// Attempts left message
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 attempt left} other{{count} attempts left}}'**
  String attemptsLeft(int count);

  /// Unlock button
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// Use biometry option
  ///
  /// In en, this message translates to:
  /// **'Use biometry'**
  String get useBiometry;

  /// Duress code title
  ///
  /// In en, this message translates to:
  /// **'Duress Code'**
  String get duressCode;

  /// Duress code description
  ///
  /// In en, this message translates to:
  /// **'Shows empty profile when entered'**
  String get duressCodeDesc;

  /// Wipe code title
  ///
  /// In en, this message translates to:
  /// **'Wipe Code'**
  String get wipeCode;

  /// Wipe code description
  ///
  /// In en, this message translates to:
  /// **'Deletes all data when entered'**
  String get wipeCodeDesc;

  /// Auto-wipe title
  ///
  /// In en, this message translates to:
  /// **'Auto-wipe'**
  String get autoWipe;

  /// Auto-wipe description
  ///
  /// In en, this message translates to:
  /// **'Wipe after {count} failed attempts'**
  String autoWipeDesc(int count);

  /// Panic gesture title
  ///
  /// In en, this message translates to:
  /// **'Panic Gesture'**
  String get panicGesture;

  /// Panic gesture description
  ///
  /// In en, this message translates to:
  /// **'3 quick app minimizes = wipe'**
  String get panicGestureDesc;

  /// Enabled state
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enabled;

  /// Disabled state
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// Setup PIN button
  ///
  /// In en, this message translates to:
  /// **'Set up PIN'**
  String get setupPin;

  /// Change PIN button
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get changePin;

  /// Remove PIN button
  ///
  /// In en, this message translates to:
  /// **'Remove PIN'**
  String get removePin;

  /// Setup duress button
  ///
  /// In en, this message translates to:
  /// **'Set up duress code'**
  String get setupDuress;

  /// Setup wipe button
  ///
  /// In en, this message translates to:
  /// **'Set up wipe code'**
  String get setupWipe;

  /// Message retention title
  ///
  /// In en, this message translates to:
  /// **'Message Retention'**
  String get messageRetention;

  /// Keep forever option
  ///
  /// In en, this message translates to:
  /// **'Forever'**
  String get retentionForever;

  /// 1 week option
  ///
  /// In en, this message translates to:
  /// **'1 week'**
  String get retentionWeek;

  /// 1 month option
  ///
  /// In en, this message translates to:
  /// **'1 month'**
  String get retentionMonth;

  /// 1 year option
  ///
  /// In en, this message translates to:
  /// **'1 year'**
  String get retentionYear;

  /// License screen title
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get license;

  /// License required message
  ///
  /// In en, this message translates to:
  /// **'License required to use the app'**
  String get licenseRequired;

  /// Activate button
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get activate;

  /// System screen title
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// Connection status title
  ///
  /// In en, this message translates to:
  /// **'Connection Status'**
  String get connectionStatus;

  /// Connected status
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// Disconnected status
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get disconnected;

  /// Connection status when the server keeps rejecting the PoP handshake
  ///
  /// In en, this message translates to:
  /// **'Authorization rejected'**
  String get authFailedStatus;

  /// Banner shown when the server keeps rejecting the PoP handshake
  ///
  /// In en, this message translates to:
  /// **'Server rejected this device\'s authorization. Check for updates.'**
  String get authFailedBanner;

  /// Reconnecting status
  ///
  /// In en, this message translates to:
  /// **'Reconnecting...'**
  String get reconnecting;

  /// Security mode title
  ///
  /// In en, this message translates to:
  /// **'Security Mode'**
  String get securityMode;

  /// Standard mode
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get standardMode;

  /// Enhanced mode
  ///
  /// In en, this message translates to:
  /// **'Enhanced Protection'**
  String get enhancedMode;

  /// Debug logs title
  ///
  /// In en, this message translates to:
  /// **'Debug Logs'**
  String get debugLogs;

  /// Clear logs button
  ///
  /// In en, this message translates to:
  /// **'Clear Logs'**
  String get clearLogs;

  /// Export logs button
  ///
  /// In en, this message translates to:
  /// **'Export Logs'**
  String get exportLogs;

  /// Logs cleared message
  ///
  /// In en, this message translates to:
  /// **'Logs cleared'**
  String get logsCleared;

  /// Calling status
  ///
  /// In en, this message translates to:
  /// **'Calling...'**
  String get calling;

  /// Ringing status
  ///
  /// In en, this message translates to:
  /// **'Ringing...'**
  String get ringing;

  /// Connecting status
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get connecting;

  /// Call ended status
  ///
  /// In en, this message translates to:
  /// **'Call ended'**
  String get callEnded;

  /// Call declined status
  ///
  /// In en, this message translates to:
  /// **'Call declined'**
  String get callDeclined;

  /// No answer status
  ///
  /// In en, this message translates to:
  /// **'No answer'**
  String get noAnswer;

  /// End call button
  ///
  /// In en, this message translates to:
  /// **'End Call'**
  String get endCall;

  /// Mute button
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get mute;

  /// Unmute button
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmute;

  /// Speaker button
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get speaker;

  /// Accept call button
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// Decline call button
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get decline;

  /// Answer incoming call button
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get answerCall;

  /// Microphone control label
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get microphone;

  /// Notification body for a new message (content hidden for privacy)
  ///
  /// In en, this message translates to:
  /// **'New message'**
  String get newMessage;

  /// Default caller/sender name when none is provided
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknownCaller;

  /// CallKit call-back action label
  ///
  /// In en, this message translates to:
  /// **'Call back'**
  String get callBack;

  /// Room/chat message notification body
  ///
  /// In en, this message translates to:
  /// **'New message in chat'**
  String get newMessageInChat;

  /// Official Orpheus notification body
  ///
  /// In en, this message translates to:
  /// **'Official Orpheus reply'**
  String get officialOrpheusReply;

  /// Test notification body
  ///
  /// In en, this message translates to:
  /// **'Test notification works! 🔔'**
  String get testNotificationWorks;

  /// Fallback incoming-call notification body
  ///
  /// In en, this message translates to:
  /// **'From: {name}'**
  String fromCaller(String name);

  /// Support chat title
  ///
  /// In en, this message translates to:
  /// **'Support Chat'**
  String get supportChat;

  /// Support welcome message
  ///
  /// In en, this message translates to:
  /// **'How can we help?'**
  String get supportWelcome;

  /// Scan QR screen title
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get scanQrTitle;

  /// Camera permission message
  ///
  /// In en, this message translates to:
  /// **'Camera permission required'**
  String get cameraPermissionRequired;

  /// Button that opens the app system settings
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettings;

  /// Help section: Quick start
  ///
  /// In en, this message translates to:
  /// **'Quick Start'**
  String get helpQuickStart;

  /// Quick start bullet 1
  ///
  /// In en, this message translates to:
  /// **'Your ID is your public key. Share it so others can add you.'**
  String get helpQuickStartBullet1;

  /// Quick start bullet 2
  ///
  /// In en, this message translates to:
  /// **'Contact works both ways: you add someone by their ID/QR, and they add you by yours.'**
  String get helpQuickStartBullet2;

  /// Quick start bullet 3
  ///
  /// In en, this message translates to:
  /// **'Chat and calls go through a secure channel, messages are encrypted.'**
  String get helpQuickStartBullet3;

  /// Help section: Export
  ///
  /// In en, this message translates to:
  /// **'Export Account (Important)'**
  String get helpExportTitle;

  /// Export bullet 1
  ///
  /// In en, this message translates to:
  /// **'Profile → Export Account shows your private key.'**
  String get helpExportBullet1;

  /// Export bullet 2
  ///
  /// In en, this message translates to:
  /// **'Private key grants full access to your account. Never share it.'**
  String get helpExportBullet2;

  /// Export bullet 3
  ///
  /// In en, this message translates to:
  /// **'Lost private key + deleted app = recovery impossible.'**
  String get helpExportBullet3;

  /// Help section: PIN
  ///
  /// In en, this message translates to:
  /// **'PIN Code'**
  String get helpPinTitle;

  /// PIN bullet 1
  ///
  /// In en, this message translates to:
  /// **'Profile → Security → PIN. If PIN is not set — access is open.'**
  String get helpPinBullet1;

  /// PIN bullet 2
  ///
  /// In en, this message translates to:
  /// **'When PIN is enabled — app locks after inactivity.'**
  String get helpPinBullet2;

  /// Help section: Duress
  ///
  /// In en, this message translates to:
  /// **'Duress Code'**
  String get helpDuressTitle;

  /// Duress bullet 1
  ///
  /// In en, this message translates to:
  /// **'This is a second PIN. When entered, shows an \"empty profile\" (0 contacts/messages).'**
  String get helpDuressBullet1;

  /// Duress bullet 2
  ///
  /// In en, this message translates to:
  /// **'Real data is not deleted — it\'s hidden while in duress mode.'**
  String get helpDuressBullet2;

  /// Help section: Wipe code
  ///
  /// In en, this message translates to:
  /// **'Wipe Code (Panic wipe)'**
  String get helpWipeCodeTitle;

  /// Wipe code bullet 1
  ///
  /// In en, this message translates to:
  /// **'A separate code for complete data deletion.'**
  String get helpWipeCodeBullet1;

  /// Wipe code bullet 2
  ///
  /// In en, this message translates to:
  /// **'After entering the code, a confirmation appears: hold the button for 2 seconds.'**
  String get helpWipeCodeBullet2;

  /// Wipe code bullet 3
  ///
  /// In en, this message translates to:
  /// **'Designed to prevent accidental wipe.'**
  String get helpWipeCodeBullet3;

  /// Help section: Auto-wipe
  ///
  /// In en, this message translates to:
  /// **'Auto-wipe'**
  String get helpAutoWipeTitle;

  /// Auto-wipe bullet 1
  ///
  /// In en, this message translates to:
  /// **'Option: delete data after N failed PIN attempts.'**
  String get helpAutoWipeBullet1;

  /// Auto-wipe bullet 2
  ///
  /// In en, this message translates to:
  /// **'Enable only if you understand the risk of irreversible data loss.'**
  String get helpAutoWipeBullet2;

  /// Help section: Panic gesture
  ///
  /// In en, this message translates to:
  /// **'Panic Gesture'**
  String get helpPanicGestureTitle;

  /// Panic gesture bullet 1
  ///
  /// In en, this message translates to:
  /// **'Option (off by default): 3 quick app minimizes → wipe.'**
  String get helpPanicGestureBullet1;

  /// Panic gesture bullet 2
  ///
  /// In en, this message translates to:
  /// **'Based on app lifecycle events, may trigger less predictably than wipe code.'**
  String get helpPanicGestureBullet2;

  /// Help section: Regions
  ///
  /// In en, this message translates to:
  /// **'Regions and Traffic Control'**
  String get helpRegionsTitle;

  /// Regions bullet 1
  ///
  /// In en, this message translates to:
  /// **'Your region is detected by a brief encrypted request to one of several independent geolocation services, which sees your IP address (as any website you visit does). Orpheus servers are not involved. If the check is unavailable, the region from your device settings is used.'**
  String get helpRegionsBullet1;

  /// Regions bullet 2
  ///
  /// In en, this message translates to:
  /// **'If a traffic-controlled region is detected, the app automatically enables \"Enhanced Protection\" mode.'**
  String get helpRegionsBullet2;

  /// Regions bullet 3
  ///
  /// In en, this message translates to:
  /// **'Connection issues? Check the System screen for network and mode status.'**
  String get helpRegionsBullet3;

  /// Select language dialog title
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get selectLanguage;

  /// System default language option
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemDefault;

  /// English language name
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// Russian language name
  ///
  /// In en, this message translates to:
  /// **'Русский'**
  String get russian;

  /// Language changed message
  ///
  /// In en, this message translates to:
  /// **'Language changed'**
  String get languageChanged;

  /// Contacts screen title
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get contactsTitle;

  /// Scan QR button tooltip
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get scanQrTooltip;

  /// Refresh button tooltip
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refreshTooltip;

  /// Loading error title
  ///
  /// In en, this message translates to:
  /// **'Loading error'**
  String get loadingError;

  /// Empty contacts subtitle
  ///
  /// In en, this message translates to:
  /// **'Add your first contact to start secure communication'**
  String get addFirstContact;

  /// Contact name hint
  ///
  /// In en, this message translates to:
  /// **'Enter name'**
  String get enterName;

  /// Short hour unit for session uptime, e.g. 2h
  ///
  /// In en, this message translates to:
  /// **'h'**
  String get unitHourShort;

  /// Short minute unit for session uptime, e.g. 5m
  ///
  /// In en, this message translates to:
  /// **'m'**
  String get unitMinuteShort;

  /// Short second unit for session uptime, e.g. 20s
  ///
  /// In en, this message translates to:
  /// **'s'**
  String get unitSecondShort;

  /// Public key label
  ///
  /// In en, this message translates to:
  /// **'Public key'**
  String get publicKey;

  /// Public key hint
  ///
  /// In en, this message translates to:
  /// **'Paste or scan key'**
  String get pasteOrScanKey;

  /// Rename action
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// Rename hint
  ///
  /// In en, this message translates to:
  /// **'Enter new name'**
  String get enterNewName;

  /// Delete contact confirmation
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String deleteContactFull(String name);

  /// Delete contact warning full
  ///
  /// In en, this message translates to:
  /// **'Contact and all chat history will be permanently deleted.'**
  String get deleteContactFullWarning;

  /// Connection status title
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get connection;

  /// Session label
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get session;

  /// Queue label
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get queue;

  /// Region label
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get region;

  /// Region subtitle when country was resolved by IP geolocation
  ///
  /// In en, this message translates to:
  /// **'IP check • encrypted'**
  String get regionSourceIp;

  /// Region subtitle when country came from the device locale
  ///
  /// In en, this message translates to:
  /// **'From device settings'**
  String get regionSourceLocale;

  /// Mode label
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get mode;

  /// Enhanced mode label
  ///
  /// In en, this message translates to:
  /// **'Enhanced'**
  String get enhanced;

  /// Standard mode label
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get standard;

  /// Enhanced protection subtitle
  ///
  /// In en, this message translates to:
  /// **'Enhanced protection'**
  String get enhancedProtection;

  /// Stable connection subtitle
  ///
  /// In en, this message translates to:
  /// **'Stable connection'**
  String get stableConnection;

  /// Encryption label
  ///
  /// In en, this message translates to:
  /// **'Encryption'**
  String get encryption;

  /// Copy fingerprint tooltip
  ///
  /// In en, this message translates to:
  /// **'Copy fingerprint'**
  String get copyFingerprint;

  /// Fingerprint label
  ///
  /// In en, this message translates to:
  /// **'Fingerprint'**
  String get fingerprint;

  /// Key created label
  ///
  /// In en, this message translates to:
  /// **'Key created'**
  String get keyCreated;

  /// E2E active message
  ///
  /// In en, this message translates to:
  /// **'End-to-end encryption active'**
  String get e2eActive;

  /// Fingerprint copied message
  ///
  /// In en, this message translates to:
  /// **'Fingerprint copied'**
  String get fingerprintCopied;

  /// Storage label
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storage;

  /// Messages label
  ///
  /// In en, this message translates to:
  /// **'messages'**
  String get messagesLabel;

  /// Contacts label
  ///
  /// In en, this message translates to:
  /// **'contacts'**
  String get contactsLabel;

  /// Application label
  ///
  /// In en, this message translates to:
  /// **'Application'**
  String get application;

  /// Device label
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get device;

  /// Model label
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// OS label
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get osLabel;

  /// Not determined label
  ///
  /// In en, this message translates to:
  /// **'Not determined'**
  String get notDetermined;

  /// Unknown label
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// Security screen title
  ///
  /// In en, this message translates to:
  /// **'SECURITY'**
  String get securityTitle;

  /// PIN code section title
  ///
  /// In en, this message translates to:
  /// **'PIN CODE'**
  String get pinCodeSection;

  /// Inactivity lock title
  ///
  /// In en, this message translates to:
  /// **'Auto-lock timeout'**
  String get inactivityLockTitle;

  /// Inactivity lock description
  ///
  /// In en, this message translates to:
  /// **'Lock after no activity'**
  String get inactivityLockDesc;

  /// Setting toggle: show the incoming caller's name while the device is locked
  ///
  /// In en, this message translates to:
  /// **'Caller name on lockscreen'**
  String get callerNameOnLockTitle;

  /// Setting description for caller name on lockscreen
  ///
  /// In en, this message translates to:
  /// **'Show the contact name on an incoming call while the phone is locked. Off by default for privacy.'**
  String get callerNameOnLockDesc;

  /// Inactivity timeout 30s
  ///
  /// In en, this message translates to:
  /// **'30 seconds'**
  String get inactivity30s;

  /// Inactivity timeout 1m
  ///
  /// In en, this message translates to:
  /// **'1 minute'**
  String get inactivity1m;

  /// Inactivity timeout 5m
  ///
  /// In en, this message translates to:
  /// **'5 minutes'**
  String get inactivity5m;

  /// Inactivity timeout 10m
  ///
  /// In en, this message translates to:
  /// **'10 minutes'**
  String get inactivity10m;

  /// PIN not set warning
  ///
  /// In en, this message translates to:
  /// **'PIN code is not set. App opens without protection.'**
  String get pinNotSet;

  /// Set PIN button
  ///
  /// In en, this message translates to:
  /// **'Set PIN code'**
  String get setPinCode;

  /// Set PIN description
  ///
  /// In en, this message translates to:
  /// **'4 or 6 digit code to protect entry'**
  String get setPinCodeDesc;

  /// PIN code set message
  ///
  /// In en, this message translates to:
  /// **'PIN code set'**
  String get pinCodeSet;

  /// Change PIN button
  ///
  /// In en, this message translates to:
  /// **'Change PIN code'**
  String get changePinCode;

  /// N-digit code
  ///
  /// In en, this message translates to:
  /// **'{count}-digit code'**
  String digitCode(int count);

  /// Disable PIN button
  ///
  /// In en, this message translates to:
  /// **'Disable PIN code'**
  String get disablePinCode;

  /// Biometry section title
  ///
  /// In en, this message translates to:
  /// **'BIOMETRY'**
  String get biometrySection;

  /// Biometry unlock option
  ///
  /// In en, this message translates to:
  /// **'Unlock with fingerprint/face'**
  String get unlockWithBiometry;

  /// Biometry option description
  ///
  /// In en, this message translates to:
  /// **'Quick entry without PIN'**
  String get quickEntryWithoutPin;

  /// Duress code section title
  ///
  /// In en, this message translates to:
  /// **'DURESS CODE'**
  String get duressCodeSection;

  /// Duress code info
  ///
  /// In en, this message translates to:
  /// **'Duress code is a second PIN that shows an empty profile. Use it if you are forced to unlock the app under pressure.'**
  String get duressCodeInfo;

  /// Set duress code button
  ///
  /// In en, this message translates to:
  /// **'Set duress code'**
  String get setDuressCode;

  /// Set duress code description
  ///
  /// In en, this message translates to:
  /// **'{count}-digit code for emergencies'**
  String setDuressCodeDesc(int count);

  /// Duress code set message
  ///
  /// In en, this message translates to:
  /// **'Duress code set ({count} digits).'**
  String duressCodeSet(int count);

  /// Disable duress code button
  ///
  /// In en, this message translates to:
  /// **'Disable duress code'**
  String get disableDuressCode;

  /// Wipe code section title
  ///
  /// In en, this message translates to:
  /// **'WIPE CODE'**
  String get wipeCodeSection;

  /// Wipe code info
  ///
  /// In en, this message translates to:
  /// **'Wipe code is a separate PIN that triggers complete data deletion. After entering, confirmation will appear: hold the button for 2 seconds (protection from accidental trigger).'**
  String get wipeCodeInfo;

  /// Set wipe code button
  ///
  /// In en, this message translates to:
  /// **'Set wipe code'**
  String get setWipeCode;

  /// Set wipe code description
  ///
  /// In en, this message translates to:
  /// **'{count}-digit panic wipe code'**
  String setWipeCodeDesc(int count);

  /// Wipe code set message
  ///
  /// In en, this message translates to:
  /// **'Wipe code set ({count} digits).'**
  String wipeCodeSet(int count);

  /// Disable wipe code button
  ///
  /// In en, this message translates to:
  /// **'Disable wipe code'**
  String get disableWipeCode;

  /// Brute force protection section title
  ///
  /// In en, this message translates to:
  /// **'BRUTE FORCE PROTECTION'**
  String get bruteForceProtection;

  /// Auto-wipe option
  ///
  /// In en, this message translates to:
  /// **'Delete data after 10 attempts'**
  String get deleteAfterAttempts;

  /// Auto-wipe description
  ///
  /// In en, this message translates to:
  /// **'Auto wipe on wrong PIN'**
  String get autoWipeOnWrongPin;

  /// Auto-wipe warning
  ///
  /// In en, this message translates to:
  /// **'After 10 wrong attempts all data will be permanently deleted!'**
  String get autoWipeWarning;

  /// Emergency wipe section title
  ///
  /// In en, this message translates to:
  /// **'EMERGENCY WIPE'**
  String get emergencyWipe;

  /// Panic gesture option
  ///
  /// In en, this message translates to:
  /// **'Enable panic wipe gesture'**
  String get enablePanicGesture;

  /// Panic gesture description
  ///
  /// In en, this message translates to:
  /// **'3 quick app minimizes → wipe (off by default)'**
  String get panicGestureFullDesc;

  /// Panic gesture warning
  ///
  /// In en, this message translates to:
  /// **'Important: this gesture is based on quick app minimizes (e.g. screen lock/unlock or quick app switching) and may be less predictable than wipe code.'**
  String get panicGestureWarning;

  /// Auto-delete messages section title
  ///
  /// In en, this message translates to:
  /// **'MESSAGE AUTO-DELETE'**
  String get autoDeleteMessages;

  /// Auto-delete info
  ///
  /// In en, this message translates to:
  /// **'Automatic deletion of old messages increases privacy. Messages older than the selected period will be permanently deleted.'**
  String get autoDeleteInfo;

  /// Confirmation dialog title
  ///
  /// In en, this message translates to:
  /// **'Confirmation'**
  String get confirmation;

  /// Delete messages confirmation
  ///
  /// In en, this message translates to:
  /// **'Enabling this policy will delete {count} messages.\n\nThis action is irreversible. Continue?'**
  String willDeleteMessages(int count);

  /// Deleted messages message
  ///
  /// In en, this message translates to:
  /// **'Deleted {count} messages'**
  String deleted(int count);

  /// Policy applied message
  ///
  /// In en, this message translates to:
  /// **'Policy applied: {name}'**
  String policyApplied(String name);

  /// Biometry enabled message
  ///
  /// In en, this message translates to:
  /// **'Biometry enabled'**
  String get biometryEnabled;

  /// Biometry failed message
  ///
  /// In en, this message translates to:
  /// **'Failed to enable biometry'**
  String get biometryFailed;

  /// Biometry confirmation prompt
  ///
  /// In en, this message translates to:
  /// **'Confirm to enable biometry'**
  String get confirmForBiometry;

  /// Fast entry label
  ///
  /// In en, this message translates to:
  /// **'Fast entry'**
  String get fastEntry;

  /// Combinations label
  ///
  /// In en, this message translates to:
  /// **'combinations'**
  String get combinations;

  /// Enhanced security label
  ///
  /// In en, this message translates to:
  /// **'Enhanced security'**
  String get enhancedSecurity;

  /// New PIN title
  ///
  /// In en, this message translates to:
  /// **'NEW PIN'**
  String get newPin;

  /// Confirm PIN title
  ///
  /// In en, this message translates to:
  /// **'CONFIRM PIN'**
  String get confirmPinTitle;

  /// Current PIN title
  ///
  /// In en, this message translates to:
  /// **'CURRENT PIN'**
  String get currentPin;

  /// Main PIN title
  ///
  /// In en, this message translates to:
  /// **'MAIN PIN'**
  String get mainPin;

  /// Duress code title
  ///
  /// In en, this message translates to:
  /// **'DURESS CODE'**
  String get duressCodeTitle;

  /// Confirm code title
  ///
  /// In en, this message translates to:
  /// **'CONFIRM CODE'**
  String get confirmCodeTitle;

  /// Wipe code title
  ///
  /// In en, this message translates to:
  /// **'WIPE CODE'**
  String get wipeCodeTitle;

  /// Enter PIN prompt
  ///
  /// In en, this message translates to:
  /// **'Enter {count}-digit PIN code'**
  String enterDigitPin(int count);

  /// Repeat PIN prompt
  ///
  /// In en, this message translates to:
  /// **'Repeat PIN code to confirm'**
  String get repeatPinToConfirm;

  /// Enter current PIN prompt
  ///
  /// In en, this message translates to:
  /// **'Enter current PIN code'**
  String get enterCurrentPin;

  /// Enter new PIN prompt
  ///
  /// In en, this message translates to:
  /// **'Enter new {count}-digit PIN code'**
  String enterNewDigitPin(int count);

  /// Repeat new PIN prompt
  ///
  /// In en, this message translates to:
  /// **'Repeat new PIN code'**
  String get repeatNewPin;

  /// Enter PIN to disable prompt
  ///
  /// In en, this message translates to:
  /// **'Enter PIN to disable'**
  String get enterPinToDisable;

  /// Confirm main PIN prompt
  ///
  /// In en, this message translates to:
  /// **'Confirm main PIN'**
  String get confirmMainPin;

  /// Enter duress code prompt
  ///
  /// In en, this message translates to:
  /// **'Enter duress code (different from main)'**
  String get enterDuressCode;

  /// Repeat duress code prompt
  ///
  /// In en, this message translates to:
  /// **'Repeat duress code'**
  String get repeatDuressCode;

  /// Enter main PIN to disable prompt
  ///
  /// In en, this message translates to:
  /// **'Enter main PIN to disable'**
  String get enterMainPinToDisable;

  /// Enter wipe code prompt
  ///
  /// In en, this message translates to:
  /// **'Enter wipe code (different from main PIN)'**
  String get enterWipeCode;

  /// Repeat wipe code prompt
  ///
  /// In en, this message translates to:
  /// **'Repeat wipe code'**
  String get repeatWipeCode;

  /// Enter main PIN to disable wipe code prompt
  ///
  /// In en, this message translates to:
  /// **'Enter main PIN to disable wipe code'**
  String get enterMainPinToDisableWipe;

  /// PIN setup screen title
  ///
  /// In en, this message translates to:
  /// **'PIN Setup'**
  String get pinSetupTitle;

  /// Change PIN screen title
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get changePinTitle;

  /// Disable PIN screen title
  ///
  /// In en, this message translates to:
  /// **'Disable PIN'**
  String get disablePinTitle;

  /// Duress code setup title
  ///
  /// In en, this message translates to:
  /// **'Duress Code'**
  String get duressCodeSetupTitle;

  /// Disable code title
  ///
  /// In en, this message translates to:
  /// **'Disable Code'**
  String get disableCodeTitle;

  /// Wipe code setup title
  ///
  /// In en, this message translates to:
  /// **'Wipe Code'**
  String get wipeCodeSetupTitle;

  /// Disable wipe code title
  ///
  /// In en, this message translates to:
  /// **'Disable Wipe Code'**
  String get disableWipeCodeTitle;

  /// PIN code set success
  ///
  /// In en, this message translates to:
  /// **'PIN code set'**
  String get pinCodeSetSuccess;

  /// PIN code changed success
  ///
  /// In en, this message translates to:
  /// **'PIN code changed'**
  String get pinCodeChangedSuccess;

  /// PIN code disabled success
  ///
  /// In en, this message translates to:
  /// **'PIN code disabled'**
  String get pinCodeDisabledSuccess;

  /// Duress code set success
  ///
  /// In en, this message translates to:
  /// **'Duress code set'**
  String get duressCodeSetSuccess;

  /// Duress code disabled success
  ///
  /// In en, this message translates to:
  /// **'Duress code disabled'**
  String get duressCodeDisabledSuccess;

  /// Wipe code set success
  ///
  /// In en, this message translates to:
  /// **'Wipe code set'**
  String get wipeCodeSetSuccess;

  /// Wipe code disabled success
  ///
  /// In en, this message translates to:
  /// **'Wipe code disabled'**
  String get wipeCodeDisabledSuccess;

  /// PINs do not match error
  ///
  /// In en, this message translates to:
  /// **'PINs do not match'**
  String get pinsDoNotMatch;

  /// Invalid PIN code error
  ///
  /// In en, this message translates to:
  /// **'Invalid PIN code'**
  String get invalidPinCode;

  /// PIN change error
  ///
  /// In en, this message translates to:
  /// **'Error changing PIN'**
  String get pinChangeError;

  /// Code must be different error
  ///
  /// In en, this message translates to:
  /// **'Code must be different from main PIN'**
  String get codeMustBeDifferent;

  /// Code setup error
  ///
  /// In en, this message translates to:
  /// **'Error setting up code'**
  String get codeSetupError;

  /// Codes do not match error
  ///
  /// In en, this message translates to:
  /// **'Codes do not match'**
  String get codesDoNotMatch;

  /// Select PIN length title
  ///
  /// In en, this message translates to:
  /// **'SELECT PIN LENGTH'**
  String get selectPinLength;

  /// PIN length description
  ///
  /// In en, this message translates to:
  /// **'Shorter PIN is faster to enter,\nlonger is more secure'**
  String get shorterPinFaster;

  /// 6 digits option
  ///
  /// In en, this message translates to:
  /// **'6 digits'**
  String get sixDigits;

  /// 4 digits option
  ///
  /// In en, this message translates to:
  /// **'4 digits'**
  String get fourDigits;

  /// Recommended label
  ///
  /// In en, this message translates to:
  /// **'recommended'**
  String get recommended;

  /// Security level title
  ///
  /// In en, this message translates to:
  /// **'Security Level'**
  String get securityLevel;

  /// 4 digit combinations
  ///
  /// In en, this message translates to:
  /// **'4-digit PIN: ~10,000 combinations'**
  String get fourDigitCombinations;

  /// 6 digit combinations
  ///
  /// In en, this message translates to:
  /// **'6-digit PIN: ~1,000,000 combinations'**
  String get sixDigitCombinations;

  /// Developer chat title
  ///
  /// In en, this message translates to:
  /// **'DEVELOPER CHAT'**
  String get developerChat;

  /// Will reply subtitle
  ///
  /// In en, this message translates to:
  /// **'We will reply soon'**
  String get willReply;

  /// Send logs dialog title
  ///
  /// In en, this message translates to:
  /// **'Send logs?'**
  String get sendLogsQuestion;

  /// Logs will be sent message
  ///
  /// In en, this message translates to:
  /// **'{count} entries will be sent.\n\nLogs help the developer understand the issue.'**
  String logsWillBeSent(int count);

  /// Send button
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// Logs sent success
  ///
  /// In en, this message translates to:
  /// **'Logs sent'**
  String get logsSent;

  /// Logs error message
  ///
  /// In en, this message translates to:
  /// **'Error sending logs'**
  String get logsError;

  /// Message not sent error
  ///
  /// In en, this message translates to:
  /// **'Failed to send message'**
  String get messageNotSent;

  /// Write to us title
  ///
  /// In en, this message translates to:
  /// **'Write to us!'**
  String get writeToUs;

  /// Support description
  ///
  /// In en, this message translates to:
  /// **'Questions, problems, suggestions — we read everything and respond.'**
  String get questionsProblemsIdeas;

  /// Developer label
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get developer;

  /// Now time label
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get now;

  /// Minutes ago
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String minAgo(int count);

  /// Days ago
  ///
  /// In en, this message translates to:
  /// **'{count} d'**
  String daysAgo(int count);

  /// Retry button
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Send logs tooltip
  ///
  /// In en, this message translates to:
  /// **'Send logs'**
  String get sendLogs;

  /// QR scan hint title
  ///
  /// In en, this message translates to:
  /// **'Point camera at QR code'**
  String get pointCameraAtQr;

  /// Shown when camera permission or init fails on the QR scanner
  ///
  /// In en, this message translates to:
  /// **'No camera access. Allow camera access to scan the QR code.'**
  String get cameraAccessDenied;

  /// QR scan hint subtitle
  ///
  /// In en, this message translates to:
  /// **'Contact\'s public key will be recognized automatically'**
  String get publicKeyAutoRecognized;

  /// Message retention - keep all
  ///
  /// In en, this message translates to:
  /// **'Keep forever'**
  String get retentionAll;

  /// Message retention - 24 hours
  ///
  /// In en, this message translates to:
  /// **'Keep 24 hours'**
  String get retentionDay;

  /// Message retention - 7 days
  ///
  /// In en, this message translates to:
  /// **'Keep 7 days'**
  String get retentionWeekOption;

  /// Message retention - 30 days
  ///
  /// In en, this message translates to:
  /// **'Keep 30 days'**
  String get retentionMonthOption;

  /// Retention all subtitle
  ///
  /// In en, this message translates to:
  /// **'Messages are not deleted automatically'**
  String get retentionAllSubtitle;

  /// Retention day subtitle
  ///
  /// In en, this message translates to:
  /// **'Messages older than a day are deleted'**
  String get retentionDaySubtitle;

  /// Retention week subtitle
  ///
  /// In en, this message translates to:
  /// **'Messages older than a week are deleted'**
  String get retentionWeekSubtitle;

  /// Retention month subtitle
  ///
  /// In en, this message translates to:
  /// **'Messages older than a month are deleted'**
  String get retentionMonthSubtitle;

  /// Auto-scroll tooltip
  ///
  /// In en, this message translates to:
  /// **'Auto-scroll'**
  String get autoScroll;

  /// Clear logs dialog title
  ///
  /// In en, this message translates to:
  /// **'Clear logs?'**
  String get clearLogsQuestion;

  /// Logs copied snackbar
  ///
  /// In en, this message translates to:
  /// **'Logs copied'**
  String get logsCopied;

  /// Log entry copied snackbar
  ///
  /// In en, this message translates to:
  /// **'Entry copied'**
  String get entryCopied;

  /// No logs message
  ///
  /// In en, this message translates to:
  /// **'No logs'**
  String get noLogs;

  /// Entries count label
  ///
  /// In en, this message translates to:
  /// **'Entries'**
  String get entries;

  /// All filter
  ///
  /// In en, this message translates to:
  /// **'ALL'**
  String get all;

  /// Done button
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Activation screen title
  ///
  /// In en, this message translates to:
  /// **'Activation'**
  String get activation;

  /// Enter code title
  ///
  /// In en, this message translates to:
  /// **'Enter code'**
  String get enterCode;

  /// Activation code hint
  ///
  /// In en, this message translates to:
  /// **'Activation code is provided upon license purchase.'**
  String get activationCodeHint;

  /// Activation code label
  ///
  /// In en, this message translates to:
  /// **'Activation code'**
  String get activationCode;

  /// Activate button
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get activateButton;

  /// Checking progress
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get checking;

  /// License activated message
  ///
  /// In en, this message translates to:
  /// **'License successfully activated.'**
  String get licenseActivated;

  /// Enter code error
  ///
  /// In en, this message translates to:
  /// **'Enter code'**
  String get enterCodeError;

  /// Invalid code error
  ///
  /// In en, this message translates to:
  /// **'Invalid code'**
  String get invalidCode;

  /// Connection error
  ///
  /// In en, this message translates to:
  /// **'Connection error. Check internet.'**
  String get connectionError;

  /// Format label
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get format;

  /// Code format hint
  ///
  /// In en, this message translates to:
  /// **'Letters, numbers, and symbols _ and -'**
  String get codeFormat;

  /// Code not accepted hint
  ///
  /// In en, this message translates to:
  /// **'If code is not accepted — check internet and input correctness.'**
  String get codeNotAccepted;

  /// Keys not initialized error
  ///
  /// In en, this message translates to:
  /// **'Keys not initialized'**
  String get keysNotInitialized;

  /// Rooms tab label
  ///
  /// In en, this message translates to:
  /// **'Rooms'**
  String get rooms;

  /// Empty rooms title
  ///
  /// In en, this message translates to:
  /// **'No rooms yet'**
  String get noRooms;

  /// Empty rooms description
  ///
  /// In en, this message translates to:
  /// **'Create or join a room to start.'**
  String get noRoomsDesc;

  /// Create room action
  ///
  /// In en, this message translates to:
  /// **'Create room'**
  String get createRoom;

  /// Join room action
  ///
  /// In en, this message translates to:
  /// **'Join room'**
  String get joinRoom;

  /// Room name input hint
  ///
  /// In en, this message translates to:
  /// **'Room name'**
  String get roomNameHint;

  /// Invite code input hint
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get inviteCodeHint;

  /// Invite code dialog title
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get inviteCodeTitle;

  /// Invite code copied message
  ///
  /// In en, this message translates to:
  /// **'Invite code copied'**
  String get inviteCodeCopied;

  /// Room created message
  ///
  /// In en, this message translates to:
  /// **'Room created'**
  String get roomCreated;

  /// Room joined message
  ///
  /// In en, this message translates to:
  /// **'Joined room'**
  String get roomJoined;

  /// Room warning banner
  ///
  /// In en, this message translates to:
  /// **'This chat is not end-to-end encrypted. Avoid sharing sensitive information.'**
  String get roomWarningUnprotected;

  /// Enable room notifications action
  ///
  /// In en, this message translates to:
  /// **'Enable chat notifications'**
  String get enableRoomNotifications;

  /// Disable room notifications action
  ///
  /// In en, this message translates to:
  /// **'Disable chat notifications'**
  String get disableRoomNotifications;

  /// Room notifications enabled snackbar
  ///
  /// In en, this message translates to:
  /// **'Chat notifications enabled'**
  String get roomNotificationsOn;

  /// Room notifications disabled snackbar
  ///
  /// In en, this message translates to:
  /// **'Chat notifications disabled'**
  String get roomNotificationsOff;

  /// Rotate invite action
  ///
  /// In en, this message translates to:
  /// **'Rotate invite code'**
  String get rotateInvite;

  /// Rotate invite confirm title
  ///
  /// In en, this message translates to:
  /// **'Rotate invite code?'**
  String get rotateInviteTitle;

  /// Rotate invite confirm description
  ///
  /// In en, this message translates to:
  /// **'Previous invite code will stop working.'**
  String get rotateInviteDesc;

  /// Panic clear action
  ///
  /// In en, this message translates to:
  /// **'Clear history for everyone'**
  String get panicClear;

  /// Panic clear confirm title
  ///
  /// In en, this message translates to:
  /// **'Clear room history?'**
  String get panicClearTitle;

  /// Panic clear confirm description
  ///
  /// In en, this message translates to:
  /// **'All messages in this room will be deleted for everyone.'**
  String get panicClearDesc;

  /// Leave room action
  ///
  /// In en, this message translates to:
  /// **'Leave room'**
  String get leaveRoom;

  /// Leave room confirm title
  ///
  /// In en, this message translates to:
  /// **'Leave room?'**
  String get leaveRoomTitle;

  /// Leave room confirm description
  ///
  /// In en, this message translates to:
  /// **'You will stop receiving messages from this room.'**
  String get leaveRoomDesc;

  /// Delete room action (owner only)
  ///
  /// In en, this message translates to:
  /// **'Delete room'**
  String get deleteRoom;

  /// Delete room confirm title
  ///
  /// In en, this message translates to:
  /// **'Delete room?'**
  String get deleteRoomTitle;

  /// Delete room confirm description
  ///
  /// In en, this message translates to:
  /// **'The room and all its messages will be permanently deleted for every member. This cannot be undone.'**
  String get deleteRoomDesc;

  /// Create button
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// Join button
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get join;

  /// Empty messages description
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get noMessagesDesc;

  /// Soft moderation warning
  ///
  /// In en, this message translates to:
  /// **'Warning: message may contain sensitive data. Be careful.'**
  String get moderationSensitiveWarning;

  /// System message when invite rotated
  ///
  /// In en, this message translates to:
  /// **'Invite code rotated. Previous code is no longer valid.'**
  String get roomSystemInviteRotated;

  /// System message when history cleared
  ///
  /// In en, this message translates to:
  /// **'Room history was cleared.'**
  String get roomSystemHistoryCleared;

  /// OK button
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// AI assistant name
  ///
  /// In en, this message translates to:
  /// **'Orpheus Oracle'**
  String get aiAssistantName;

  /// AI assistant short name
  ///
  /// In en, this message translates to:
  /// **'AI Assistant'**
  String get aiAssistantShortName;

  /// AI online status
  ///
  /// In en, this message translates to:
  /// **'Always online'**
  String get aiAssistantOnline;

  /// AI assistant description
  ///
  /// In en, this message translates to:
  /// **'Smart Orpheus helper'**
  String get aiAssistantDesc;

  /// AI welcome message
  ///
  /// In en, this message translates to:
  /// **'Hello! I\'m your personal AI consultant for Orpheus. Ask me anything about app features, security, or settings.'**
  String get aiAssistantWelcome;

  /// AI thinking indicator
  ///
  /// In en, this message translates to:
  /// **'Thinking...'**
  String get aiThinking;

  /// AI message input hint
  ///
  /// In en, this message translates to:
  /// **'Ask a question...'**
  String get aiMessageHint;

  /// Clear AI chat button
  ///
  /// In en, this message translates to:
  /// **'Clear chat'**
  String get aiClearChat;

  /// Clear AI chat dialog title
  ///
  /// In en, this message translates to:
  /// **'Clear history?'**
  String get aiClearChatTitle;

  /// Clear AI chat dialog description
  ///
  /// In en, this message translates to:
  /// **'AI conversation history will be deleted.'**
  String get aiClearChatDesc;

  /// Clear AI memory button
  ///
  /// In en, this message translates to:
  /// **'Clear memory'**
  String get aiClearMemory;

  /// Clear AI memory dialog title
  ///
  /// In en, this message translates to:
  /// **'Clear memory?'**
  String get aiClearMemoryTitle;

  /// Clear AI memory dialog description
  ///
  /// In en, this message translates to:
  /// **'AI memory and dialog history will be deleted.'**
  String get aiClearMemoryDesc;

  /// AI memory indicator
  ///
  /// In en, this message translates to:
  /// **'Memory: {count} AI replies'**
  String aiMemoryIndicator(int count);

  /// AI suggestion 1
  ///
  /// In en, this message translates to:
  /// **'What\'s new in this version?'**
  String get aiSuggestion1;

  /// AI suggestion 2
  ///
  /// In en, this message translates to:
  /// **'How does encryption work?'**
  String get aiSuggestion2;

  /// AI suggestion 3
  ///
  /// In en, this message translates to:
  /// **'What is the duress code?'**
  String get aiSuggestion3;

  /// AI suggestion 4
  ///
  /// In en, this message translates to:
  /// **'What is the Oracle of Orpheus?'**
  String get aiSuggestion4;

  /// Notes vault title
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get notesVaultTitle;

  /// Notes vault subtitle
  ///
  /// In en, this message translates to:
  /// **'Personal notes and important messages'**
  String get notesVaultDesc;

  /// Empty notes title
  ///
  /// In en, this message translates to:
  /// **'Vault is empty'**
  String get notesEmptyTitle;

  /// Empty notes subtitle
  ///
  /// In en, this message translates to:
  /// **'Save thoughts and important messages here'**
  String get notesEmptyDesc;

  /// Notes input placeholder
  ///
  /// In en, this message translates to:
  /// **'New note...'**
  String get notesPlaceholder;

  /// Save note button
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get notesAdd;

  /// Add to notes action
  ///
  /// In en, this message translates to:
  /// **'Add to notes'**
  String get notesAddFromChat;

  /// Note added snackbar
  ///
  /// In en, this message translates to:
  /// **'Added to notes'**
  String get notesAdded;

  /// Delete note title
  ///
  /// In en, this message translates to:
  /// **'Delete note?'**
  String get notesDeleteTitle;

  /// Delete note description
  ///
  /// In en, this message translates to:
  /// **'The note will be deleted permanently.'**
  String get notesDeleteDesc;

  /// Note source from contact
  ///
  /// In en, this message translates to:
  /// **'From chat with {name}'**
  String notesFromContact(String name);

  /// Note source from room
  ///
  /// In en, this message translates to:
  /// **'From room {name}'**
  String notesFromRoom(String name);

  /// Note source from Oracle
  ///
  /// In en, this message translates to:
  /// **'From Oracle chat'**
  String get notesFromOracle;

  /// Contacts search field hint
  ///
  /// In en, this message translates to:
  /// **'Search contacts'**
  String get searchContactsHint;

  /// Empty contacts search results
  ///
  /// In en, this message translates to:
  /// **'No contacts found'**
  String get noContactsFound;

  /// Chat menu: contact info item
  ///
  /// In en, this message translates to:
  /// **'Contact info'**
  String get contactInfo;

  /// Hint for verifying a contact's public key against MITM
  ///
  /// In en, this message translates to:
  /// **'Compare this key with your contact over a trusted channel to make sure no one is intercepting your messages.'**
  String get verifyKeyHint;

  /// Button to open in-app license purchase
  ///
  /// In en, this message translates to:
  /// **'Buy license'**
  String get buyLicense;

  /// Purchase screen title
  ///
  /// In en, this message translates to:
  /// **'Buy Premium'**
  String get premiumPurchaseTitle;

  /// Plan selection heading
  ///
  /// In en, this message translates to:
  /// **'Choose a plan'**
  String get choosePlan;

  /// Plan selection subtitle
  ///
  /// In en, this message translates to:
  /// **'Pay with USDT (TRC-20). Your license activates automatically after payment.'**
  String get choosePlanHint;

  /// Error loading tariffs
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load plans. Check your connection and try again.'**
  String get plansLoadError;

  /// Error creating an invoice
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create the payment. Please try again.'**
  String get createInvoiceError;

  /// Warning to send on the correct network
  ///
  /// In en, this message translates to:
  /// **'Send ONLY USDT on the TRON network (TRC-20). Funds sent on any other network will be lost.'**
  String get paymentNetworkWarning;

  /// Label for the payment address
  ///
  /// In en, this message translates to:
  /// **'Wallet address'**
  String get walletAddress;

  /// Label for the amount to pay
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amountToPay;

  /// Hint under the payment QR code
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code with your USDT (TRC-20) wallet, or copy the address below.'**
  String get scanQrHint;

  /// Payment pending status
  ///
  /// In en, this message translates to:
  /// **'Awaiting payment…'**
  String get awaitingPayment;

  /// Hint under the awaiting-payment status
  ///
  /// In en, this message translates to:
  /// **'This screen unlocks automatically once the payment is confirmed (about a minute).'**
  String get awaitingPaymentHint;

  /// Button to force a payment status re-check
  ///
  /// In en, this message translates to:
  /// **'I\'ve paid'**
  String get iPaid;

  /// Invoice expired message
  ///
  /// In en, this message translates to:
  /// **'The payment time has expired.'**
  String get invoiceExpired;

  /// Button to start a new invoice
  ///
  /// In en, this message translates to:
  /// **'New invoice'**
  String get newInvoice;

  /// Success dialog title
  ///
  /// In en, this message translates to:
  /// **'Payment confirmed'**
  String get paymentConfirmedTitle;

  /// Success dialog body
  ///
  /// In en, this message translates to:
  /// **'Your license is now active. Welcome to Orpheus.'**
  String get paymentConfirmedBody;

  /// Edit note menu item
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editNote;

  /// Rotate invite confirm button (short)
  ///
  /// In en, this message translates to:
  /// **'Rotate'**
  String get rotateConfirm;

  /// Clear room history confirm button (short)
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get panicClearConfirm;

  /// Leave room confirm button (short)
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get leaveConfirm;

  /// Delete room confirm button (short)
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteConfirm;

  /// Server switch dialog title
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get serverSwitchTitle;

  /// Production server option
  ///
  /// In en, this message translates to:
  /// **'Production'**
  String get serverProduction;

  /// Test server option
  ///
  /// In en, this message translates to:
  /// **'Test server'**
  String get serverTest;

  /// Current active host label
  ///
  /// In en, this message translates to:
  /// **'Current: {host}'**
  String serverCurrent(String host);

  /// Test connection button
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get serverTestConnection;

  /// Connection OK result
  ///
  /// In en, this message translates to:
  /// **'Reachable ({ms} ms)'**
  String serverConnectionOk(int ms);

  /// Connection failed result
  ///
  /// In en, this message translates to:
  /// **'Server unreachable'**
  String get serverConnectionFailed;

  /// Apply server switch button
  ///
  /// In en, this message translates to:
  /// **'Apply & reconnect'**
  String get serverApply;

  /// Reset to production button
  ///
  /// In en, this message translates to:
  /// **'Reset to production'**
  String get serverResetProd;

  /// Banner shown when a non-production host is active
  ///
  /// In en, this message translates to:
  /// **'TEST SERVER'**
  String get serverTestBanner;

  /// Snackbar after switching server
  ///
  /// In en, this message translates to:
  /// **'Switched to {host}'**
  String serverSwitched(String host);
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  Future<L10n> load(Locale locale) {
    return SynchronousFuture<L10n>(lookupL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_L10nDelegate old) => false;
}

L10n lookupL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return L10nEn();
    case 'ru':
      return L10nRu();
  }

  throw FlutterError(
      'L10n.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
