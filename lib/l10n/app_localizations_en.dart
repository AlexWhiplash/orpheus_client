// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class L10nEn extends L10n {
  L10nEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Orpheus';

  @override
  String get welcomeSubtitle => 'Secure communication without the noise';

  @override
  String get createAccount => 'Create Account';

  @override
  String get restoreFromKey => 'Restore from Key';

  @override
  String get e2eEncryption => 'End-to-end encryption';

  @override
  String get recovery => 'Recovery';

  @override
  String get recoveryWarning =>
      'Private key grants full access to your account. Never share it with anyone.';

  @override
  String get pastePrivateKey => 'Paste private key...';

  @override
  String get cancel => 'Cancel';

  @override
  String get import => 'Import';

  @override
  String get error => 'Error';

  @override
  String get profile => 'Profile';

  @override
  String get qrCode => 'QR Code';

  @override
  String get yourId => 'Your ID';

  @override
  String get idCopied => 'ID copied';

  @override
  String get share => 'Share';

  @override
  String shareMessage(String key) {
    return 'Hi! Add me on Orpheus.\nMy key:\n$key';
  }

  @override
  String contactsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'contacts',
      one: 'contact',
      zero: 'contacts',
    );
    return '$_temp0';
  }

  @override
  String messagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'messages',
      one: 'message',
      zero: 'messages',
    );
    return '$_temp0';
  }

  @override
  String get sentCount => 'sent';

  @override
  String get security => 'Security';

  @override
  String get securityDesc => 'PIN, duress, wipe';

  @override
  String get support => 'Support';

  @override
  String get supportDesc => 'Contact developer';

  @override
  String get howToUse => 'How to Use';

  @override
  String get howToUseDesc => 'Quick guide';

  @override
  String get updateHistory => 'Update History';

  @override
  String get updateAvailable => 'Update Available';

  @override
  String updateMessageRequired(String version) {
    return 'New version $version is available.\nThis is a critical security update.';
  }

  @override
  String updateMessageOptional(String version) {
    return 'New version $version is available.\nWe recommend updating for stable operation.';
  }

  @override
  String get updateLater => 'Later';

  @override
  String get updateDownload => 'Download';

  @override
  String get updateDownloading => 'Downloading Update';

  @override
  String get updateUpToDate => 'You have the latest version';

  @override
  String get updateInstallError => 'Installation Error';

  @override
  String get updateInstallErrorMessage =>
      'Could not install the update automatically. You can download it via browser.';

  @override
  String get updateOpenBrowser => 'Open in Browser';

  @override
  String get exportAccount => 'Export Account';

  @override
  String get exportAccountDesc => 'Show private key';

  @override
  String get notificationSettings => 'Notification Settings';

  @override
  String get notificationSettingsDesc => 'For Android (Vivo, Xiaomi, etc.)';

  @override
  String get orpheusNotificationsDesc =>
      'Notifications for messages in Orpheus public chat.';

  @override
  String get orpheusOfficialNotifications => 'Official Orpheus replies';

  @override
  String get systemNotificationSettings => 'System notification settings';

  @override
  String get language => 'Language';

  @override
  String get languageDesc => 'English, Русский';

  @override
  String accountCreated(String date) {
    return 'Account created $date';
  }

  @override
  String get checkUpdates => 'Check';

  @override
  String get deleteAccount => 'Delete Account';

  @override
  String get deleteAccountTitle => 'Delete Account?';

  @override
  String get deleteAccountWarning =>
      'This will delete keys, contacts and message history without possibility of recovery.';

  @override
  String get deleteAccountConfirm => 'I understand this is irreversible';

  @override
  String get delete => 'Delete';

  @override
  String get deleteForBoth => 'Delete for both';

  @override
  String get deleteForBothConfirm =>
      'Delete for both? The message will also be removed on the recipient\'s device.';

  @override
  String nSelected(int count) {
    return '$count selected';
  }

  @override
  String deleteSelectedConfirm(int count) {
    return 'Delete $count messages?';
  }

  @override
  String get selectMessages => 'Select';

  @override
  String get privateKey => 'Private Key';

  @override
  String get privateKeyWarning =>
      'Never share this key with anyone. Possession of it grants full access to your account.';

  @override
  String get close => 'Close';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get keyCopied => 'Key copied';

  @override
  String get biometryUnavailable =>
      'Biometry unavailable. Set up device security.';

  @override
  String get confirmIdentity => 'Confirm identity to export keys';

  @override
  String get authError => 'Authentication error';

  @override
  String get accountDeleted => 'Account deleted. Restart the app.';

  @override
  String get online => 'Online';

  @override
  String get offline => 'Offline';

  @override
  String get call => 'Call';

  @override
  String get menu => 'Menu';

  @override
  String get clearHistory => 'Clear History?';

  @override
  String get clearHistoryWarning =>
      'All messages with this contact will be permanently deleted.';

  @override
  String get startConversation => 'Start a conversation';

  @override
  String get messagesEncrypted => 'Messages are encrypted and stored locally.';

  @override
  String get messagePlaceholder => 'Message...';

  @override
  String get writeAsOrpheus => 'Write as Orpheus';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get incomingCall => 'Incoming call';

  @override
  String get outgoingCall => 'Outgoing call';

  @override
  String get missedCall => 'Missed call';

  @override
  String get callLabel => 'Call';

  @override
  String get incoming => 'Incoming';

  @override
  String get outgoing => 'Outgoing';

  @override
  String get chats => 'Chats';

  @override
  String get contacts => 'Contacts';

  @override
  String get settings => 'Settings';

  @override
  String get orpheusRoomName => 'Orpheus';

  @override
  String get orpheusOfficialBadge => 'OFFICIAL';

  @override
  String get orpheusOfficialName => 'Orpheus';

  @override
  String get orpheusRoomWarning => 'Public chat. Do not share personal data.';

  @override
  String get orpheusRoomUnavailable =>
      'Orpheus public chat is not available yet. Check the server or try again later.';

  @override
  String get noChats => 'No chats yet';

  @override
  String get noChatsDesc => 'Add a contact to start messaging';

  @override
  String get addContact => 'Add Contact';

  @override
  String get noContacts => 'No contacts';

  @override
  String get noContactsDesc => 'Scan QR code or paste contact\'s ID';

  @override
  String get scanQr => 'Scan QR';

  @override
  String get addById => 'Add by ID';

  @override
  String get newContact => 'New Contact';

  @override
  String get contactName => 'Name';

  @override
  String get contactId => 'Contact ID';

  @override
  String get add => 'Add';

  @override
  String get fillAllFields => 'Please fill in both fields';

  @override
  String get invalidPublicKey => 'Invalid key format';

  @override
  String get contactAdded => 'Contact added';

  @override
  String get contactExists => 'Contact already exists';

  @override
  String get invalidId => 'Invalid ID format';

  @override
  String get cannotAddSelf => 'Cannot add yourself';

  @override
  String get deleteContact => 'Delete Contact?';

  @override
  String get deleteContactWarning =>
      'Contact and chat history will be deleted.';

  @override
  String get contactDeleted => 'Contact deleted';

  @override
  String get renameContact => 'Rename Contact';

  @override
  String get save => 'Save';

  @override
  String get pinCode => 'PIN Code';

  @override
  String get enterPin => 'Enter PIN';

  @override
  String get confirmPin => 'Confirm PIN';

  @override
  String get pinMismatch => 'PINs do not match';

  @override
  String get pinSet => 'PIN set';

  @override
  String get pinDisabled => 'PIN disabled';

  @override
  String get wrongPin => 'Wrong PIN';

  @override
  String attemptsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attempts left',
      one: '1 attempt left',
    );
    return '$_temp0';
  }

  @override
  String get unlock => 'Unlock';

  @override
  String get useBiometry => 'Use biometry';

  @override
  String get duressCode => 'Duress Code';

  @override
  String get duressCodeDesc => 'Shows empty profile when entered';

  @override
  String get wipeCode => 'Wipe Code';

  @override
  String get wipeCodeDesc => 'Deletes all data when entered';

  @override
  String get autoWipe => 'Auto-wipe';

  @override
  String autoWipeDesc(int count) {
    return 'Wipe after $count failed attempts';
  }

  @override
  String get panicGesture => 'Panic Gesture';

  @override
  String get panicGestureDesc => '3 quick app minimizes = wipe';

  @override
  String get enabled => 'Enabled';

  @override
  String get disabled => 'Disabled';

  @override
  String get setupPin => 'Set up PIN';

  @override
  String get changePin => 'Change PIN';

  @override
  String get removePin => 'Remove PIN';

  @override
  String get setupDuress => 'Set up duress code';

  @override
  String get setupWipe => 'Set up wipe code';

  @override
  String get messageRetention => 'Message Retention';

  @override
  String get retentionForever => 'Forever';

  @override
  String get retentionWeek => '1 week';

  @override
  String get retentionMonth => '1 month';

  @override
  String get retentionYear => '1 year';

  @override
  String get license => 'License';

  @override
  String get licenseRequired => 'License required to use the app';

  @override
  String get activate => 'Activate';

  @override
  String get system => 'System';

  @override
  String get connectionStatus => 'Connection Status';

  @override
  String get connected => 'Connected';

  @override
  String get disconnected => 'Disconnected';

  @override
  String get reconnecting => 'Reconnecting...';

  @override
  String get securityMode => 'Security Mode';

  @override
  String get standardMode => 'Standard';

  @override
  String get enhancedMode => 'Enhanced Protection';

  @override
  String get debugLogs => 'Debug Logs';

  @override
  String get clearLogs => 'Clear Logs';

  @override
  String get exportLogs => 'Export Logs';

  @override
  String get logsCleared => 'Logs cleared';

  @override
  String get calling => 'Calling...';

  @override
  String get ringing => 'Ringing...';

  @override
  String get connecting => 'Connecting...';

  @override
  String get callEnded => 'Call ended';

  @override
  String get callDeclined => 'Call declined';

  @override
  String get noAnswer => 'No answer';

  @override
  String get endCall => 'End Call';

  @override
  String get mute => 'Mute';

  @override
  String get unmute => 'Unmute';

  @override
  String get speaker => 'Speaker';

  @override
  String get accept => 'Accept';

  @override
  String get decline => 'Decline';

  @override
  String get answerCall => 'Answer';

  @override
  String get microphone => 'Microphone';

  @override
  String get newMessage => 'New message';

  @override
  String get unknownCaller => 'Unknown';

  @override
  String get callBack => 'Call back';

  @override
  String get newMessageInChat => 'New message in chat';

  @override
  String get officialOrpheusReply => 'Official Orpheus reply';

  @override
  String get testNotificationWorks => 'Test notification works! 🔔';

  @override
  String fromCaller(String name) {
    return 'From: $name';
  }

  @override
  String get supportChat => 'Support Chat';

  @override
  String get supportWelcome => 'How can we help?';

  @override
  String get scanQrTitle => 'Scan QR Code';

  @override
  String get cameraPermissionRequired => 'Camera permission required';

  @override
  String get openSettings => 'Open settings';

  @override
  String get helpQuickStart => 'Quick Start';

  @override
  String get helpQuickStartBullet1 =>
      'Your ID is your public key. Share it so others can add you.';

  @override
  String get helpQuickStartBullet2 =>
      'Contact works both ways: you add someone by their ID/QR, and they add you by yours.';

  @override
  String get helpQuickStartBullet3 =>
      'Chat and calls go through a secure channel, messages are encrypted.';

  @override
  String get helpExportTitle => 'Export Account (Important)';

  @override
  String get helpExportBullet1 =>
      'Profile → Export Account shows your private key.';

  @override
  String get helpExportBullet2 =>
      'Private key grants full access to your account. Never share it.';

  @override
  String get helpExportBullet3 =>
      'Lost private key + deleted app = recovery impossible.';

  @override
  String get helpPinTitle => 'PIN Code';

  @override
  String get helpPinBullet1 =>
      'Profile → Security → PIN. If PIN is not set — access is open.';

  @override
  String get helpPinBullet2 =>
      'When PIN is enabled — app locks after inactivity.';

  @override
  String get helpDuressTitle => 'Duress Code';

  @override
  String get helpDuressBullet1 =>
      'This is a second PIN. When entered, shows an \"empty profile\" (0 contacts/messages).';

  @override
  String get helpDuressBullet2 =>
      'Real data is not deleted — it\'s hidden while in duress mode.';

  @override
  String get helpWipeCodeTitle => 'Wipe Code (Panic wipe)';

  @override
  String get helpWipeCodeBullet1 =>
      'A separate code for complete data deletion.';

  @override
  String get helpWipeCodeBullet2 =>
      'After entering the code, a confirmation appears: hold the button for 2 seconds.';

  @override
  String get helpWipeCodeBullet3 => 'Designed to prevent accidental wipe.';

  @override
  String get helpAutoWipeTitle => 'Auto-wipe';

  @override
  String get helpAutoWipeBullet1 =>
      'Option: delete data after N failed PIN attempts.';

  @override
  String get helpAutoWipeBullet2 =>
      'Enable only if you understand the risk of irreversible data loss.';

  @override
  String get helpPanicGestureTitle => 'Panic Gesture';

  @override
  String get helpPanicGestureBullet1 =>
      'Option (off by default): 3 quick app minimizes → wipe.';

  @override
  String get helpPanicGestureBullet2 =>
      'Based on app lifecycle events, may trigger less predictably than wipe code.';

  @override
  String get helpRegionsTitle => 'Regions and Traffic Control';

  @override
  String get helpRegionsBullet1 =>
      'Your region is determined locally on your device and is never sent to Orpheus servers or any third party.';

  @override
  String get helpRegionsBullet2 =>
      'If a traffic-controlled region is detected, the app automatically enables \"Enhanced Protection\" mode.';

  @override
  String get helpRegionsBullet3 =>
      'Connection issues? Check the System screen for network and mode status.';

  @override
  String get selectLanguage => 'Select Language';

  @override
  String get systemDefault => 'System default';

  @override
  String get english => 'English';

  @override
  String get russian => 'Русский';

  @override
  String get languageChanged => 'Language changed';

  @override
  String get contactsTitle => 'Contacts';

  @override
  String get scanQrTooltip => 'Scan QR';

  @override
  String get refreshTooltip => 'Refresh';

  @override
  String get loadingError => 'Loading error';

  @override
  String get addFirstContact =>
      'Add your first contact to start secure communication';

  @override
  String get enterName => 'Enter contact name';

  @override
  String get publicKey => 'Public key';

  @override
  String get pasteOrScanKey => 'Paste or scan key';

  @override
  String get rename => 'Rename';

  @override
  String get enterNewName => 'Enter new name';

  @override
  String deleteContactFull(String name) {
    return 'Delete $name?';
  }

  @override
  String get deleteContactFullWarning =>
      'Contact and all chat history will be permanently deleted.';

  @override
  String get connection => 'Connection';

  @override
  String get session => 'Session';

  @override
  String get queue => 'Queue';

  @override
  String get region => 'Region';

  @override
  String get regionLocalOnly => 'Local only • never sent';

  @override
  String get mode => 'Mode';

  @override
  String get enhanced => 'Enhanced';

  @override
  String get standard => 'Standard';

  @override
  String get enhancedProtection => 'Enhanced protection';

  @override
  String get stableConnection => 'Stable connection';

  @override
  String get encryption => 'Encryption';

  @override
  String get copyFingerprint => 'Copy fingerprint';

  @override
  String get fingerprint => 'Fingerprint';

  @override
  String get keyCreated => 'Key created';

  @override
  String get e2eActive => 'End-to-end encryption active';

  @override
  String get fingerprintCopied => 'Fingerprint copied';

  @override
  String get storage => 'Storage';

  @override
  String get messagesLabel => 'messages';

  @override
  String get contactsLabel => 'contacts';

  @override
  String get application => 'Application';

  @override
  String get device => 'Device';

  @override
  String get model => 'Model';

  @override
  String get osLabel => 'System';

  @override
  String get notDetermined => 'Not determined';

  @override
  String get unknown => 'Unknown';

  @override
  String get securityTitle => 'SECURITY';

  @override
  String get pinCodeSection => 'PIN CODE';

  @override
  String get inactivityLockTitle => 'Auto-lock timeout';

  @override
  String get inactivityLockDesc => 'Lock after no activity';

  @override
  String get inactivity30s => '30 seconds';

  @override
  String get inactivity1m => '1 minute';

  @override
  String get inactivity5m => '5 minutes';

  @override
  String get inactivity10m => '10 minutes';

  @override
  String get pinNotSet => 'PIN code is not set. App opens without protection.';

  @override
  String get setPinCode => 'Set PIN code';

  @override
  String get setPinCodeDesc => '4 or 6 digit code to protect entry';

  @override
  String get pinCodeSet => 'PIN code set';

  @override
  String get changePinCode => 'Change PIN code';

  @override
  String digitCode(int count) {
    return '$count-digit code';
  }

  @override
  String get disablePinCode => 'Disable PIN code';

  @override
  String get biometrySection => 'BIOMETRY';

  @override
  String get unlockWithBiometry => 'Unlock with fingerprint/face';

  @override
  String get quickEntryWithoutPin => 'Quick entry without PIN';

  @override
  String get duressCodeSection => 'DURESS CODE';

  @override
  String get duressCodeInfo =>
      'Duress code is a second PIN that shows an empty profile. Use it if you are forced to unlock the app under pressure.';

  @override
  String get setDuressCode => 'Set duress code';

  @override
  String setDuressCodeDesc(int count) {
    return '$count-digit code for emergencies';
  }

  @override
  String duressCodeSet(int count) {
    return 'Duress code set ($count digits).';
  }

  @override
  String get disableDuressCode => 'Disable duress code';

  @override
  String get wipeCodeSection => 'WIPE CODE';

  @override
  String get wipeCodeInfo =>
      'Wipe code is a separate PIN that triggers complete data deletion. After entering, confirmation will appear: hold the button for 2 seconds (protection from accidental trigger).';

  @override
  String get setWipeCode => 'Set wipe code';

  @override
  String setWipeCodeDesc(int count) {
    return '$count-digit panic wipe code';
  }

  @override
  String wipeCodeSet(int count) {
    return 'Wipe code set ($count digits).';
  }

  @override
  String get disableWipeCode => 'Disable wipe code';

  @override
  String get bruteForceProtection => 'BRUTE FORCE PROTECTION';

  @override
  String get deleteAfterAttempts => 'Delete data after 10 attempts';

  @override
  String get autoWipeOnWrongPin => 'Auto wipe on wrong PIN';

  @override
  String get autoWipeWarning =>
      'After 10 wrong attempts all data will be permanently deleted!';

  @override
  String get emergencyWipe => 'EMERGENCY WIPE';

  @override
  String get enablePanicGesture => 'Enable panic wipe gesture';

  @override
  String get panicGestureFullDesc =>
      '3 quick app minimizes → wipe (off by default)';

  @override
  String get panicGestureWarning =>
      'Important: this gesture is based on quick app minimizes (e.g. screen lock/unlock or quick app switching) and may be less predictable than wipe code.';

  @override
  String get autoDeleteMessages => 'MESSAGE AUTO-DELETE';

  @override
  String get autoDeleteInfo =>
      'Automatic deletion of old messages increases privacy. Messages older than the selected period will be permanently deleted.';

  @override
  String get confirmation => 'Confirmation';

  @override
  String willDeleteMessages(int count) {
    return 'Enabling this policy will delete $count messages.\n\nThis action is irreversible. Continue?';
  }

  @override
  String deleted(int count) {
    return 'Deleted $count messages';
  }

  @override
  String policyApplied(String name) {
    return 'Policy applied: $name';
  }

  @override
  String get biometryEnabled => 'Biometry enabled';

  @override
  String get biometryFailed => 'Failed to enable biometry';

  @override
  String get confirmForBiometry => 'Confirm to enable biometry';

  @override
  String get fastEntry => 'Fast entry';

  @override
  String get combinations => 'combinations';

  @override
  String get enhancedSecurity => 'Enhanced security';

  @override
  String get newPin => 'NEW PIN';

  @override
  String get confirmPinTitle => 'CONFIRM PIN';

  @override
  String get currentPin => 'CURRENT PIN';

  @override
  String get mainPin => 'MAIN PIN';

  @override
  String get duressCodeTitle => 'DURESS CODE';

  @override
  String get confirmCodeTitle => 'CONFIRM CODE';

  @override
  String get wipeCodeTitle => 'WIPE CODE';

  @override
  String enterDigitPin(int count) {
    return 'Enter $count-digit PIN code';
  }

  @override
  String get repeatPinToConfirm => 'Repeat PIN code to confirm';

  @override
  String get enterCurrentPin => 'Enter current PIN code';

  @override
  String enterNewDigitPin(int count) {
    return 'Enter new $count-digit PIN code';
  }

  @override
  String get repeatNewPin => 'Repeat new PIN code';

  @override
  String get enterPinToDisable => 'Enter PIN to disable';

  @override
  String get confirmMainPin => 'Confirm main PIN';

  @override
  String get enterDuressCode => 'Enter duress code (different from main)';

  @override
  String get repeatDuressCode => 'Repeat duress code';

  @override
  String get enterMainPinToDisable => 'Enter main PIN to disable';

  @override
  String get enterWipeCode => 'Enter wipe code (different from main PIN)';

  @override
  String get repeatWipeCode => 'Repeat wipe code';

  @override
  String get enterMainPinToDisableWipe => 'Enter main PIN to disable wipe code';

  @override
  String get pinSetupTitle => 'PIN Setup';

  @override
  String get changePinTitle => 'Change PIN';

  @override
  String get disablePinTitle => 'Disable PIN';

  @override
  String get duressCodeSetupTitle => 'Duress Code';

  @override
  String get disableCodeTitle => 'Disable Code';

  @override
  String get wipeCodeSetupTitle => 'Wipe Code';

  @override
  String get disableWipeCodeTitle => 'Disable Wipe Code';

  @override
  String get pinCodeSetSuccess => 'PIN code set';

  @override
  String get pinCodeChangedSuccess => 'PIN code changed';

  @override
  String get pinCodeDisabledSuccess => 'PIN code disabled';

  @override
  String get duressCodeSetSuccess => 'Duress code set';

  @override
  String get duressCodeDisabledSuccess => 'Duress code disabled';

  @override
  String get wipeCodeSetSuccess => 'Wipe code set';

  @override
  String get wipeCodeDisabledSuccess => 'Wipe code disabled';

  @override
  String get pinsDoNotMatch => 'PINs do not match';

  @override
  String get invalidPinCode => 'Invalid PIN code';

  @override
  String get pinChangeError => 'Error changing PIN';

  @override
  String get codeMustBeDifferent => 'Code must be different from main PIN';

  @override
  String get codeSetupError => 'Error setting up code';

  @override
  String get codesDoNotMatch => 'Codes do not match';

  @override
  String get selectPinLength => 'SELECT PIN LENGTH';

  @override
  String get shorterPinFaster =>
      'Shorter PIN is faster to enter,\nlonger is more secure';

  @override
  String get sixDigits => '6 digits';

  @override
  String get fourDigits => '4 digits';

  @override
  String get recommended => 'recommended';

  @override
  String get securityLevel => 'Security Level';

  @override
  String get fourDigitCombinations => '4-digit PIN: ~10,000 combinations';

  @override
  String get sixDigitCombinations => '6-digit PIN: ~1,000,000 combinations';

  @override
  String get developerChat => 'DEVELOPER CHAT';

  @override
  String get willReply => 'We will reply soon';

  @override
  String get sendLogsQuestion => 'Send logs?';

  @override
  String logsWillBeSent(int count) {
    return '$count entries will be sent.\n\nLogs help the developer understand the issue.';
  }

  @override
  String get send => 'Send';

  @override
  String get logsSent => 'Logs sent';

  @override
  String get logsError => 'Error sending logs';

  @override
  String get messageNotSent => 'Failed to send message';

  @override
  String get writeToUs => 'Write to us!';

  @override
  String get questionsProblemsIdeas =>
      'Questions, problems, suggestions — we read everything and respond.';

  @override
  String get developer => 'Developer';

  @override
  String get now => 'now';

  @override
  String minAgo(int count) {
    return '$count min';
  }

  @override
  String daysAgo(int count) {
    return '$count d';
  }

  @override
  String get retry => 'Retry';

  @override
  String get sendLogs => 'Send logs';

  @override
  String get pointCameraAtQr => 'Point camera at QR code';

  @override
  String get cameraAccessDenied =>
      'No camera access. Allow camera access to scan the QR code.';

  @override
  String get publicKeyAutoRecognized =>
      'Contact\'s public key will be recognized automatically';

  @override
  String get retentionAll => 'Keep forever';

  @override
  String get retentionDay => 'Keep 24 hours';

  @override
  String get retentionWeekOption => 'Keep 7 days';

  @override
  String get retentionMonthOption => 'Keep 30 days';

  @override
  String get retentionAllSubtitle => 'Messages are not deleted automatically';

  @override
  String get retentionDaySubtitle => 'Messages older than a day are deleted';

  @override
  String get retentionWeekSubtitle => 'Messages older than a week are deleted';

  @override
  String get retentionMonthSubtitle =>
      'Messages older than a month are deleted';

  @override
  String get autoScroll => 'Auto-scroll';

  @override
  String get clearLogsQuestion => 'Clear logs?';

  @override
  String get logsCopied => 'Logs copied';

  @override
  String get entryCopied => 'Entry copied';

  @override
  String get noLogs => 'No logs';

  @override
  String get entries => 'Entries';

  @override
  String get all => 'ALL';

  @override
  String get done => 'Done';

  @override
  String get activation => 'Activation';

  @override
  String get enterCode => 'Enter code';

  @override
  String get activationCodeHint =>
      'Activation code is provided upon license purchase.';

  @override
  String get activationCode => 'Activation code';

  @override
  String get activateButton => 'Activate';

  @override
  String get checking => 'Checking…';

  @override
  String get licenseActivated => 'License successfully activated.';

  @override
  String get enterCodeError => 'Enter code';

  @override
  String get invalidCode => 'Invalid code';

  @override
  String get connectionError => 'Connection error. Check internet.';

  @override
  String get format => 'Format';

  @override
  String get codeFormat => 'Letters, numbers, and symbols _ and -';

  @override
  String get codeNotAccepted =>
      'If code is not accepted — check internet and input correctness.';

  @override
  String get keysNotInitialized => 'Keys not initialized';

  @override
  String get rooms => 'Rooms';

  @override
  String get noRooms => 'No rooms yet';

  @override
  String get noRoomsDesc => 'Create or join a room to start.';

  @override
  String get createRoom => 'Create room';

  @override
  String get joinRoom => 'Join room';

  @override
  String get roomNameHint => 'Room name';

  @override
  String get inviteCodeHint => 'Invite code';

  @override
  String get inviteCodeTitle => 'Invite code';

  @override
  String get inviteCodeCopied => 'Invite code copied';

  @override
  String get roomCreated => 'Room created';

  @override
  String get roomJoined => 'Joined room';

  @override
  String get roomWarningUnprotected =>
      'This chat is not end-to-end encrypted. Avoid sharing sensitive information.';

  @override
  String get enableRoomNotifications => 'Enable chat notifications';

  @override
  String get disableRoomNotifications => 'Disable chat notifications';

  @override
  String get roomNotificationsOn => 'Chat notifications enabled';

  @override
  String get roomNotificationsOff => 'Chat notifications disabled';

  @override
  String get rotateInvite => 'Rotate invite code';

  @override
  String get rotateInviteTitle => 'Rotate invite code?';

  @override
  String get rotateInviteDesc => 'Previous invite code will stop working.';

  @override
  String get panicClear => 'Clear history for everyone';

  @override
  String get panicClearTitle => 'Clear room history?';

  @override
  String get panicClearDesc =>
      'All messages in this room will be deleted for everyone.';

  @override
  String get leaveRoom => 'Leave room';

  @override
  String get leaveRoomTitle => 'Leave room?';

  @override
  String get leaveRoomDesc =>
      'You will stop receiving messages from this room.';

  @override
  String get create => 'Create';

  @override
  String get join => 'Join';

  @override
  String get noMessagesDesc => 'No messages yet';

  @override
  String get moderationSensitiveWarning =>
      'Warning: message may contain sensitive data. Be careful.';

  @override
  String get roomSystemInviteRotated =>
      'Invite code rotated. Previous code is no longer valid.';

  @override
  String get roomSystemHistoryCleared => 'Room history was cleared.';

  @override
  String get ok => 'OK';

  @override
  String get aiAssistantName => 'Orpheus Oracle';

  @override
  String get aiAssistantShortName => 'AI Assistant';

  @override
  String get aiAssistantOnline => 'Always online';

  @override
  String get aiAssistantDesc => 'Smart Orpheus helper';

  @override
  String get aiAssistantWelcome =>
      'Hello! I\'m your personal AI consultant for Orpheus. Ask me anything about app features, security, or settings.';

  @override
  String get aiThinking => 'Thinking...';

  @override
  String get aiMessageHint => 'Ask a question...';

  @override
  String get aiClearChat => 'Clear chat';

  @override
  String get aiClearChatTitle => 'Clear history?';

  @override
  String get aiClearChatDesc => 'AI conversation history will be deleted.';

  @override
  String get aiClearMemory => 'Clear memory';

  @override
  String get aiClearMemoryTitle => 'Clear memory?';

  @override
  String get aiClearMemoryDesc =>
      'AI memory and dialog history will be deleted.';

  @override
  String aiMemoryIndicator(int count) {
    return 'Memory: $count AI replies';
  }

  @override
  String get aiSuggestion1 => 'What\'s new in this version?';

  @override
  String get aiSuggestion2 => 'How does encryption work?';

  @override
  String get aiSuggestion3 => 'What is the duress code?';

  @override
  String get aiSuggestion4 => 'What is the Oracle of Orpheus?';

  @override
  String get notesVaultTitle => 'Vault';

  @override
  String get notesVaultDesc => 'Personal notes and important messages';

  @override
  String get notesEmptyTitle => 'Vault is empty';

  @override
  String get notesEmptyDesc => 'Save thoughts and important messages here';

  @override
  String get notesPlaceholder => 'New note...';

  @override
  String get notesAdd => 'Save';

  @override
  String get notesAddFromChat => 'Add to notes';

  @override
  String get notesAdded => 'Added to notes';

  @override
  String get notesDeleteTitle => 'Delete note?';

  @override
  String get notesDeleteDesc => 'The note will be deleted permanently.';

  @override
  String notesFromContact(String name) {
    return 'From chat with $name';
  }

  @override
  String notesFromRoom(String name) {
    return 'From room $name';
  }

  @override
  String get notesFromOracle => 'From Oracle chat';

  @override
  String get searchContactsHint => 'Search contacts';

  @override
  String get noContactsFound => 'No contacts found';
}
