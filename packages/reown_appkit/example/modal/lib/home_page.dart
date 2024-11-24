import 'dart:developer';
import 'dart:convert';

import 'package:fl_toast/fl_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:reown_appkit_example/services/deep_link_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;

import 'package:reown_appkit/reown_appkit.dart';

import 'package:reown_appkit_example/widgets/debug_drawer.dart';
import 'package:reown_appkit_example/utils/constants.dart';
import 'package:reown_appkit_example/services/siwe_service.dart';
import 'package:reown_appkit_example/widgets/logger_widget.dart';
import 'package:reown_appkit_example/widgets/session_widget.dart';
import 'package:reown_appkit_example/utils/dart_defines.dart';

// Define the Perk model
class Perk {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final ShapeBorder shape;

  Perk({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.shape,
  });
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.prefs,
    required this.bundleId,
    required this.toggleBrightness,
    required this.toggleTheme,
  });

  final VoidCallback toggleBrightness;
  final VoidCallback toggleTheme;
  final SharedPreferences prefs;
  final String bundleId;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // final overlay = OverlayController(const Duration(milliseconds: 200));
  final M1NTY_ACCOUNT_ID = 'e44dce98-3e47-4eef-852e-2a9c91d34915';
  late OverlayController overlay;

  late ReownAppKitModal _appKitModal;
  late SIWESampleWebService _siweTestService;
  late VideoPlayerController _videoController;
  bool _initialized = false;

  bool _showSuccess = false;

  String? _pendingAction;

  // Add this list to manage NFTs
  List<String> _nftList = [
    'NFT #1',
    'NFT #2',
    // 'NFT #3',
    // 'NFT #4',
    // 'NFT #5',
  ];

  // Add this list to manage Perks
  List<Perk> _perkList = [];

  @override
  void initState() {
    super.initState();
    _siweTestService = SIWESampleWebService();
    _videoController = VideoPlayerController.asset('assets/movie.mp4')
      ..initialize().then((_) {
        setState(() {});
        _videoController.play();
        _videoController.setLooping(true);
      });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeService(widget.prefs);
    });
  }

  void _toggleOverlay() {
    overlay.show(context);
  }

  String get _flavor {
    // String flavor = '-${const String.fromEnvironment('FLUTTER_APP_FLAVOR')}';
    // return flavor.replaceAll('-production', '');
    final internal = widget.bundleId.endsWith('.internal');
    final debug = widget.bundleId.endsWith('.debug');
    if (internal || debug || kDebugMode) {
      return '-internal';
    }
    return '';
  }

  String _universalLink() {
    Uri link = Uri.parse('https://m1nty.app/flutter_appkit_modal');
    if (_flavor.isNotEmpty && !kDebugMode) {
      return link.replace(path: '${link.path}_internal').toString();
    }
    return link.toString();
  }

  Redirect _constructRedirect() {
    return Redirect(
      native: 'web3modalflutter://',
      universal: _universalLink(),
      // enable linkMode on Wallet so Dapps can use relay-less connection
      // universal: value must be set on cloud config as well
      linkMode: true,
    );
  }

  PairingMetadata _pairingMetadata() {
    return PairingMetadata(
      name: StringConstants.pageTitle,
      description: StringConstants.pageTitle,
      url: _universalLink(),
      icons: [
        'https://raw.githubusercontent.com/reown-com/reown_flutter/refs/heads/develop/assets/appkit_logo.png',
      ],
      redirect: _constructRedirect(),
    );
  }

  SIWEConfig _siweConfig(bool enabled) => SIWEConfig(
        getNonce: () async {
          // this has to be called at the very moment of creating the pairing uri
          try {
            debugPrint('[SIWEConfig] getNonce()');
            final response = await _siweTestService.getNonce();
            return response['nonce'] as String;
          } catch (error) {
            debugPrint('[SIWEConfig] getNonce error: $error');
            // Fallback patch for testing purposes in case SIWE backend has issues
            return SIWEUtils.generateNonce();
          }
        },
        getMessageParams: () async {
          // Provide everything that is needed to construct the SIWE message
          debugPrint('[SIWEConfig] getMessageParams()');
          debugPrint(MethodsConstants.allMethods.toString());
          final url = _pairingMetadata().url;
          final uri = Uri.parse(url);
          return SIWEMessageArgs(
            domain: uri.authority,
            uri: 'https://${uri.authority}/login',
            statement: 'Welcome to AppKit $packageVersion for Flutter.',
            methods: MethodsConstants.allMethods,
          );
        },
        createMessage: (SIWECreateMessageArgs args) {
          // Create SIWE message to be signed.
          // You can use our provided formatMessage() method of implement your own
          debugPrint('[SIWEConfig] createMessage()');
          return SIWEUtils.formatMessage(args);
        },
        verifyMessage: (SIWEVerifyMessageArgs args) async {
          try {
            debugPrint('[SIWEConfig] verifyMessage()');
            debugPrint('Message: ${args.message}');
            debugPrint('Signature: ${args.signature}');

            final message = args.message;
            final signature = args.signature;

            if (message == null || signature == null) {
              debugPrint('[SIWEConfig] Message or signature is null');
              return false;
            }

            final payload = {
              'message': message,
              'signature': signature,
            };

            final url = _pairingMetadata().url;
            final uri = Uri.parse(url);
            final result = await _siweTestService.verifyMessage(
              payload,
              domain: uri.authority,
            );

            debugPrint('Verification result: $result');
            return result['token'] != null;
          } catch (error) {
            debugPrint('[SIWEConfig] verifyMessage error: $error');
            return false;
          }
        },
        getSession: () async {
          // Return proper session from your Web Service
          try {
            debugPrint('[SIWEConfig] getSession()');
            final session = await _siweTestService.getSession();
            final address = session['address']!.toString();
            final chainId = session['chainId']!.toString();
            return SIWESession(address: address, chains: [chainId]);
          } catch (error) {
            debugPrint('[SIWEConfig] getSession error: $error');
            // Fallback patch for testing purposes in case SIWE backend has issues
            final chainId = _appKitModal.selectedChain?.chainId ?? '1';
            final namespace = ReownAppKitModalNetworks.getNamespaceForChainId(
              chainId,
            );
            final address = _appKitModal.session!.getAddress(namespace)!;
            return SIWESession(address: address, chains: [chainId]);
          }
        },
        onSignIn: (SIWESession session) {
          // Called after SIWE message is signed and verified
          debugPrint('[SIWEConfig] onSignIn()');
        },
        signOut: () async {
          // Called when user taps on disconnect button
          try {
            debugPrint('[SIWEConfig] signOut()');
            final _ = await _siweTestService.signOut();
            return true;
          } catch (error) {
            debugPrint('[SIWEConfig] signOut error: $error');
            // Fallback patch for testing purposes in case SIWE backend has issues
            return true;
          }
        },
        onSignOut: () {
          // Called when disconnecting WalletConnect session was successfull
          debugPrint('[SIWEConfig] onSignOut()');
        },
        enabled: enabled,
        signOutOnDisconnect: true,
        signOutOnAccountChange: true,
        signOutOnNetworkChange: true,
        // nonceRefetchIntervalMs: 300000,
        // sessionRefetchIntervalMs: 300000,
      );

  void _initializeService(SharedPreferences prefs) async {
    // Clear all shared preferences
    // await prefs.clear();

    final analyticsValue = prefs.getBool('appkit_analytics') ?? true;
    final emailWalletValue = prefs.getBool('appkit_email_wallet') ?? true;
    final siweAuthValue = prefs.getBool('appkit_siwe_auth') ?? true;
    // final siweAuthValue = false;

    ReownAppKitModalNetworks.removeTestNetworks();
    ReownAppKitModalNetworks.removeSupportedNetworks('solana');
    // final testNetworks = <ReownAppKitModalNetworkInfo>[];

    // Add this network as the first entry
    final etherlink = ReownAppKitModalNetworkInfo(
      name: 'Etherlink',
      chainId: '42793',
      currency: 'XTZ',
      rpcUrl: 'https://node.mainnet.etherlink.com',
      explorerUrl: 'https://etherlink.io',
      chainIcon: 'https://cryptologos.cc/logos/tezos-xtz-logo.png',
      isTestNetwork: false,
    );

    ReownAppKitModalNetworks.addSupportedNetworks('eip155', [etherlink]);

    try {
      _appKitModal = ReownAppKitModal(
        context: context,
        projectId: DartDefines.projectId,
        logLevel: LogLevel.all,
        metadata: _pairingMetadata(),
        siweConfig: _siweConfig(siweAuthValue),
        enableAnalytics: analyticsValue, // OPTIONAL - null by default
        featuresConfig: FeaturesConfig(
          email: emailWalletValue,
          socials: [
            // AppKitSocialOption.Farcaster,
            // AppKitSocialOption.Google,
            AppKitSocialOption.Apple,
            AppKitSocialOption.X,
            AppKitSocialOption.Discord,
          ],
          showMainWallets: false, // OPTIONAL - true by default
        ),
        // requiredNamespaces: {},
        optionalNamespaces: siweAuthValue
            ? null
            : {
                'eip155': RequiredNamespace.fromJson({
                  'chains': ReownAppKitModalNetworks.getAllSupportedNetworks(
                    namespace: 'eip155',
                  ).map((chain) => 'eip155:${chain.chainId}').toList(),
                  'methods':
                      NetworkUtils.defaultNetworkMethods['eip155']!.toList(),
                  'events':
                      NetworkUtils.defaultNetworkEvents['eip155']!.toList(),
                })
                // 'solana': RequiredNamespace.fromJson({
                //   'chains': ReownAppKitModalNetworks.getAllSupportedNetworks(
                //     namespace: 'solana',
                //   ).map((chain) => 'solana:${chain.chainId}').toList(),
                //   'methods':
                //       NetworkUtils.defaultNetworkMethods['solana']!.toList(),
                //   'events': [],
                // }),
                // 'polkadot': RequiredNamespace.fromJson({
                //   'chains': [
                //     'polkadot:91b171bb158e2d3848fa23a9f1c25182',
                //     'polkadot:e143f23803ac50e8f6f8e62695d1ce9e'
                //   ],
                //   'methods': [
                //     'polkadot_signMessage',
                //     'polkadot_signTransaction',
                //   ],
                //   'events': []
              },
        includedWalletIds: {
          // 'f71e9b2c658264f7c6dfe938bbf9d2a025acc7ba4245eea2356e2995b1fd24d3', // m1nty
          // 'c57ca95b47569778a828d19178114f4db188b89b763c899ba0be274e97267d96', // Metamask
          // 'fd20dc426fb37566d803205b19bbc1d4096b248ac04548e3cfb6b3a38bd033aa', // Coinbase
          // '4622a2b2d6af1c9844944291e5e7351a6aa24cd7b23099efac1b2fd875da31a0', //trust wallet
          // 'c03dfee351b6fcc421b4494ea33b9d4b92a984f87aa76d1663bb28705e95034a', //uniswap
          // '1ae92b26df02f0abca6304df07debccd18262fdf5fe82daa81593582dac9a369', //rainbow
          // '225affb176778569276e484e1b92637ad061b01e13a048b35a9d280c3b58970f' //safe
        },
        featuredWalletIds: {
          //   //m1nty
          'f71e9b2c658264f7c6dfe938bbf9d2a025acc7ba4245eea2356e2995b1fd24d3', // m1nty
          //   // 'fd20dc426fb37566d803205b19bbc1d4096b248ac04548e3cfb6b3a38bd033aa', // Coinbase
          //   // '18450873727504ae9315a084fa7624b5297d2fe5880f0982979c17345a138277', // Kraken Wallet
          'c57ca95b47569778a828d19178114f4db188b89b763c899ba0be274e97267d96', // Metamask
          //   // '1ae92b26df02f0abca6304df07debccd18262fdf5fe82daa81593582dac9a369', // Rainbow
          //   // 'c03dfee351b6fcc421b4494ea33b9d4b92a984f87aa76d1663bb28705e95034a', // Uniswap
          //   // '38f5d18bd8522c244bdd70cb4a68e0e718865155811c043f052fb9f1c51de662', // Bitget
        },
        // excludedWalletIds: {
        //   'fd20dc426fb37566d803205b19bbc1d4096b248ac04548e3cfb6b3a38bd033aa', // Coinbase
        // },
        // MORE WALLETS https://explorer.walletconnect.com/?type=wallet&chains=eip155%3A1
      );

      overlay = OverlayController(
        const Duration(milliseconds: 200),
        appKitModal: _appKitModal,
      );

      _toggleOverlay();

      setState(() => _initialized = true);
    } on ReownAppKitModalException catch (e) {
      debugPrint('⛔️ ${e.message}');
      return;
    }
    // modal specific subscriptions
    _appKitModal.onModalConnect.subscribe(_onModalConnect);
    _appKitModal.onModalUpdate.subscribe(_onModalUpdate);
    _appKitModal.onModalNetworkChange.subscribe(_onModalNetworkChange);
    _appKitModal.onModalDisconnect.subscribe(_onModalDisconnect);
    _appKitModal.onModalError.subscribe(_onModalError);
    // session related subscriptions
    _appKitModal.onSessionExpireEvent.subscribe(_onSessionExpired);
    _appKitModal.onSessionUpdateEvent.subscribe(_onSessionUpdate);
    _appKitModal.onSessionEventEvent.subscribe(_onSessionEvent);

    // relayClient subscriptions
    _appKitModal.appKit!.core.relayClient.onRelayClientConnect.subscribe(
      _onRelayClientConnect,
    );
    _appKitModal.appKit!.core.relayClient.onRelayClientError.subscribe(
      _onRelayClientError,
    );
    _appKitModal.appKit!.core.relayClient.onRelayClientDisconnect.subscribe(
      _onRelayClientDisconnect,
    );
    // _appKitModal.appKit!.core.addLogListener(_logListener);

    //
    await _appKitModal.init();

    DeepLinkHandler.init(_appKitModal);
    DeepLinkHandler.checkInitialLink();

    setState(() {});
  }

  // void _logListener(event) {
  //   if ('${event.level}' == 'Level.debug' ||
  //       '${event.level}' == 'Level.error') {
  //     // TODO send to mixpanel
  //     log('${event.message}');
  //   } else {
  //     debugPrint('${event.message}');
  //   }
  // }

  @override
  void dispose() {
    debugPrint(
        '[ExampleApp] Disposing _MyHomePageState and initiating disconnect.');

    _videoController.dispose();

    // Initiate disconnect and log the outcome
    _appKitModal.disconnect().then((_) {
      debugPrint('[ExampleApp] Successfully disconnected from session.');
    }).catchError((error) {
      debugPrint('[ExampleApp] Error while disconnecting: $error');
    });

    // Unsubscribe from all events
    // _appKitModal.appKit!.core.removeLogListener(_logListener);
    _appKitModal.appKit!.core.relayClient.onRelayClientConnect
        .unsubscribe(_onRelayClientConnect);
    _appKitModal.appKit!.core.relayClient.onRelayClientError
        .unsubscribe(_onRelayClientError);
    _appKitModal.appKit!.core.relayClient.onRelayClientDisconnect
        .unsubscribe(_onRelayClientDisconnect);

    _appKitModal.onModalConnect.unsubscribe(_onModalConnect);
    _appKitModal.onModalUpdate.unsubscribe(_onModalUpdate);
    _appKitModal.onModalNetworkChange.unsubscribe(_onModalNetworkChange);
    _appKitModal.onModalDisconnect.unsubscribe(_onModalDisconnect);
    _appKitModal.onModalError.unsubscribe(_onModalError);

    _appKitModal.onSessionExpireEvent.unsubscribe(_onSessionExpired);
    _appKitModal.onSessionUpdateEvent.unsubscribe(_onSessionUpdate);
    _appKitModal.onSessionEventEvent.unsubscribe(_onSessionEvent);

    super.dispose();
  }

  void _handlePendingAction() {
    if (_pendingAction != null && _appKitModal.isConnected) {
      final chainId = _appKitModal.selectedChain?.chainId ?? '1';
      final namespace = ReownAppKitModalNetworks.getNamespaceForChainId(
        chainId,
      );
      final address = _appKitModal.session!.getAddress(namespace)!;
      final email = _appKitModal.session!.email;
      switch (_pendingAction) {
        case 'mint':
          mintToken(address, email);
          break;
        case 'loyalty':
          getLoyalty(address);
          break;
      }

      // Clear pending action after handling
      setState(() => _pendingAction = null);
    }
  }

  void mintToken(String address, String email) async {
    debugPrint('THIS WOULD BE SDK CALL');
    debugPrint('Minting token for address: $address, email: $email');

    //delay 1 second
    await Future.delayed(const Duration(seconds: 1));

    // Simulate a successful minting process
    setState(() {
      final newNftNumber = _nftList.length + 1;
      _nftList.add('NFT #$newNftNumber');
      _showSuccess = true;
    });
    // Optionally, show a success message
    // showTextToast(text: 'NFT Minted Successfully!', context: context);
  }

  void getLoyalty(String address) async {
    // Existing debug prints...
    debugPrint('THIS WOULD BE SDK CALL');
    debugPrint('Getting loyalty offers for address: $address');

    // Simulate fetching perks
    await Future.delayed(const Duration(seconds: 1));

    setState(() {
      _perkList = [
        Perk(
          title: 'Discount',
          description: 'Get 10% off on your next purchase',
          icon: Icons.discount,
          color: Colors.blueAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
        ),
        Perk(
          title: 'Early Access',
          description: 'Access new features before everyone else',
          icon: Icons.lock_clock,
          color: Colors.greenAccent,
          shape: CircleBorder(),
        ),
        Perk(
          title: 'Free Shipping',
          description: 'Enjoy free shipping on all orders',
          icon: Icons.local_shipping,
          color: Colors.orangeAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
        ),
        Perk(
          title: 'Exclusive Content',
          description: 'Unlock exclusive articles and videos',
          icon: Icons.video_library,
          color: Colors.purpleAccent,
          shape: StadiumBorder(),
        ),
      ];
    });
  }

  void _onModalConnect(ModalConnect? event) async {
    setState(() {});
    debugPrint('[ExampleApp] _onModalConnect ${event?.session.toJson()}');

    // Notify m1nty API that a wallet has connected
    _notifyWalletConnected(event?.session, DateTime.now());

    // Handle pending action immediately after connection
    _handlePendingAction();
  }

  void _onModalUpdate(ModalConnect? event) {
    // _appKitModal.appKit!.authKeys.storage.deleteAll();

    setState(() {});
  }

  void _onModalNetworkChange(ModalNetworkChange? event) {
    debugPrint('[ExampleApp] _onModalNetworkChange ${event?.toString()}');
    setState(() {});
  }

  void _onModalDisconnect(ModalDisconnect? event) {
    debugPrint('[ExampleApp] _onModalDisconnect triggered.');
    debugPrint('[ExampleApp] Disconnect event details: ${event?.toString()}');

    // Log current session state before disconnect
    debugPrint(
        '[ExampleApp] Session before disconnect: ${_appKitModal.session?.toJson()}');

    setState(() {});
  }

  void _onModalError(ModalError? event) {
    debugPrint('[ExampleApp] _onModalError ${event?.toString()}');
    // When user connected to Coinbase Wallet but Coinbase Wallet does not have a session anymore
    // (for instance if user disconnected the dapp directly within Coinbase Wallet)
    // Then Coinbase Wallet won't emit any event
    if ((event?.message ?? '').contains('Coinbase Wallet Error')) {
      _appKitModal.disconnect();
    }
    setState(() {});
  }

  void _onSessionExpired(SessionExpire? event) {
    debugPrint('[ExampleApp] _onSessionExpired ${event?.toString()}');
    setState(() {});
  }

  void _onSessionUpdate(SessionUpdate? event) {
    debugPrint('[ExampleApp] _onSessionUpdate ${event?.toString()}');
    setState(() {});
  }

  void _onSessionEvent(SessionEvent? event) {
    debugPrint('[ExampleApp] _onSessionEvent ${event?.toString()}');
    setState(() {});
  }

  void _onRelayClientConnect(EventArgs? event) {
    setState(() {});
    showTextToast(text: 'Relay connected', context: context);
  }

  void _onRelayClientError(EventArgs? event) {
    setState(() {});
    showTextToast(text: 'Relay disconnected', context: context);
  }

  void _onRelayClientDisconnect(EventArgs? event) {
    setState(() {});
    showTextToast(
      text: 'Relay disconnected: ${event?.toString()}',
      context: context,
    );
  }

  Future<void> _notifyWalletConnected(
      ReownAppKitModalSession? session, DateTime timestamp) async {
    final address = getWalletAddress();
    debugPrint('NOTIFY CONNECT..... ${address} ');
    debugPrint('THIS WOULD BE SDK CALL');

    if (session == null) return;

    final namespace = ReownAppKitModalNetworks.getNamespaceForChainId(
      session.chainId,
    );
    debugPrint('Session: ${session.getAddress(namespace)}');

    try {
      final response = await http.post(
        Uri.parse(
            'https://ki7luz9ns2.execute-api.eu-west-1.amazonaws.com/prod/log-wallet'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'action': 'connect',
          'account': M1NTY_ACCOUNT_ID,
          'address': address,
          'email': session.email,
          'timestamp': timestamp.toIso8601String(),
          'chainId': session.chainId,
        }),
      );

      if (response.statusCode == 201) {
        debugPrint('Successfully notified wallet connection');
      } else {
        debugPrint(
            'Failed to notify wallet connection: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error notifying wallet connection: $e');
    }
  }

  /// Retrieves the wallet address based on the selected chain's namespace.
  String? getWalletAddress() {
    final chainId = _appKitModal.selectedChain?.chainId ?? '1';
    final namespace = ReownAppKitModalNetworks.getNamespaceForChainId(chainId);
    debugPrint('Namespace: $namespace');

    return _appKitModal.session?.getAddress(namespace);
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return SizedBox.shrink();
    }
    return Scaffold(
      backgroundColor: ReownAppKitModalTheme.colorsOf(context).background125,
      appBar: AppBar(
        elevation: 0.0,
        title: Image.asset(
          'assets/logo.png',
          height: 60,
        ),
        backgroundColor: ReownAppKitModalTheme.colorsOf(context).background175,
        foregroundColor: ReownAppKitModalTheme.colorsOf(context).foreground100,
      ),
      body: !_initialized
          ? const SizedBox.shrink()
          : RefreshIndicator(
              onRefresh: () => _refreshData(),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Text('Watch the live stream',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                    ),
                    if (_videoController.value.isInitialized)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Column(
                          children: [
                            // Video player
                            AspectRatio(
                              aspectRatio: _videoController.value.aspectRatio,
                              child: Stack(
                                alignment: Alignment.bottomCenter,
                                children: [
                                  VideoPlayer(_videoController),
                                  _VideoControls(
                                    controller: _videoController,
                                    appKit: _appKitModal,
                                    showSuccess: _showSuccess,
                                    onSuccessShown: () {
                                      setState(() {
                                        _showSuccess = false; // Reset the flag
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                            // Controls below video
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      _videoController.value.isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                    ),
                                    onPressed: () {
                                      _videoController.value.isPlaying
                                          ? _videoController.pause()
                                          : _videoController.play();
                                    },
                                  ),
                                  Expanded(
                                    child: VideoProgressIndicator(
                                      _videoController,
                                      allowScrubbing: true,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8.0),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox.square(dimension: 6.0),
                    _ButtonsView(appKit: _appKitModal),
                    _ConnectedView(
                      appKit: _appKitModal,
                      nftList: _nftList,
                      perkList: _perkList,
                    ),
                  ],
                ),
              ),
            ),
      endDrawer: Drawer(
        backgroundColor: ReownAppKitModalTheme.colorsOf(context).background125,
        child: DebugDrawer(
          toggleOverlay: _toggleOverlay,
          toggleBrightness: widget.toggleBrightness,
          toggleTheme: widget.toggleTheme,
          appKitModal: _appKitModal,
        ),
      ),
      onEndDrawerChanged: (isOpen) {
        // write your callback implementation here
        if (isOpen) return;
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return const AlertDialog(
              content: Text(
                'If you made changes you\'ll need to restart the app',
              ),
            );
          },
        );
      },
      // floatingActionButton: CircleAvatar(
      //   radius: 6.0,
      //   backgroundColor: _initialized &&
      //           _appKitModal.appKit?.core.relayClient.isConnected == true
      //       ? Colors.green
      //       : Colors.red,
      // ),
    );
  }

  Future<void> _refreshData() async {
    await _appKitModal.reconnectRelay();
    await _appKitModal.loadAccountData();
    setState(() {});
  }
}

class _ButtonsView extends StatelessWidget {
  const _ButtonsView({required this.appKit});
  final ReownAppKitModal appKit;

  @override
  Widget build(BuildContext context) {
    final homeState = context.findAncestorStateOfType<_MyHomePageState>();
    final address = homeState?.getWalletAddress();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AppKitModalAccountButton(
            appKitModal: appKit, custom: const SizedBox.shrink()),

        AppKitModalConnectButton(
          appKit: appKit,
          custom: ElevatedButton(
            onPressed: () {
              if (!appKit.isConnected) {
                homeState?._pendingAction = 'loyalty';
                appKit.openModalView(ReownAppKitModalMainWalletsPage());
              } else if (address != null) {
                homeState?.getLoyalty(address);
              }
            },
            child: address != null
                ? Text('${address.substring(0, 7)}...')
                : const Text('Get loyalty offers'),
          ),
        ),
        // If connected, show the "Show Perks" button
        if (appKit.isConnected)
          ElevatedButton(
            onPressed: () {
              debugPrint('Selected Chain ID: ${appKit.selectedChain?.chainId}');
              debugPrint(
                  'Session: ${appKit.session?.toJson()}'); // Log full session data

              final chainId = appKit.selectedChain?.chainId ?? '1';
              final namespace =
                  ReownAppKitModalNetworks.getNamespaceForChainId(chainId);
              debugPrint('Namespace: $namespace');

              final address = appKit.session?.getAddress(namespace);
              debugPrint('Address from namespace: $address');

              if (address != null) {
                homeState?.getLoyalty(address);
              } else {
                debugPrint('Error: Could not get wallet address');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not get wallet address'),
                  ),
                );
              }
            },
            child: const Text('Show Perks'),
          ),
      ],
    );
  }
}

class _ConnectedView extends StatelessWidget {
  const _ConnectedView({
    required this.appKit,
    required this.nftList,
    required this.perkList,
  });

  final ReownAppKitModal appKit;
  final List<String> nftList;
  final List<Perk> perkList;

  @override
  Widget build(BuildContext context) {
    if (!appKit.isConnected) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // AppKitModalAccountButton(appKitModal: appKit),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppKitModalBalanceButton(
              appKitModal: appKit,
              onTap: appKit.openModalView,
            ),
            const SizedBox.square(dimension: 8.0),
            AppKitModalAddressButton(
              appKitModal: appKit,
              onTap: appKit.openModalView,
            ),
          ],
        ),

        const SizedBox.square(dimension: 5.0),
        // Pass the NFT list here
        _NFTGridView(nftList: nftList),
        // Perk Grid View
        _PerkGridView(perkList: perkList),
      ],
    );
  }
}

// Add this new widget
class _NFTGridView extends StatelessWidget {
  const _NFTGridView({required this.nftList});

  final List<String> nftList;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Your Loyalty NFTs',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: nftList.length,
          itemBuilder: (context, index) {
            return Card(
              elevation: 4,
              color: const Color.fromARGB(255, 40, 40, 40).withOpacity(0.9),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.image,
                    size: 40,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    nftList[index],
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _PerkGridView extends StatelessWidget {
  const _PerkGridView({required this.perkList});

  final List<Perk> perkList;

  @override
  Widget build(BuildContext context) {
    if (perkList.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Your Perks',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, // Adjust the number of columns as needed
            crossAxisSpacing: 30,
            mainAxisSpacing: 30,
          ),
          itemCount: perkList.length,
          itemBuilder: (context, index) {
            final perk = perkList[index];
            return Card(
              shape: perk.shape,
              color: perk.color,
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      perk.icon,
                      size: 40,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      perk.title,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      perk.description,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _VideoControls extends StatefulWidget {
  const _VideoControls({
    required this.controller,
    required this.appKit,
    required this.showSuccess,
    required this.onSuccessShown,
    Key? key,
  }) : super(key: key);

  final VideoPlayerController controller;
  final ReownAppKitModal appKit;
  final bool showSuccess;
  final VoidCallback onSuccessShown;

  @override
  State<_VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<_VideoControls>
    with SingleTickerProviderStateMixin {
  late AnimationController _overlayController;
  late Animation<Offset> _slideAnimation;
  bool _showSuccess = false;

  @override
  void initState() {
    super.initState();
    _overlayController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeOut,
    ));

    Future.delayed(const Duration(seconds: 2), () {
      _overlayController.forward();
    });
  }

  @override
  void didUpdateWidget(covariant _VideoControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.showSuccess && widget.showSuccess) {
      showSuccess();
    }
  }

  @override
  void dispose() {
    _overlayController.dispose();
    super.dispose();
  }

  Future<void> _handleGoPress() async {
    final appKit = widget.appKit;
    if (!appKit.isConnected) {
      debugPrint('Setting pending action: mint');
      final homeState = context.findAncestorStateOfType<_MyHomePageState>();
      if (homeState != null) {
        homeState._pendingAction = 'mint';
        appKit.openModalView(ReownAppKitModalMainWalletsPage());
      }
    } else {
      final chainId = appKit.selectedChain?.chainId ?? '1';
      final namespace =
          ReownAppKitModalNetworks.getNamespaceForChainId(chainId);
      final address = appKit.session?.getAddress(namespace);
      final email = appKit.session?.email;

      if (address != null && email != null) {
        final homeState = context.findAncestorStateOfType<_MyHomePageState>();
        homeState?.mintToken(address, email);
        // Show success animation and slide out
        showSuccess();
      } else {
        debugPrint('Error: Could not get wallet address');
        // Optionally show an error message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not get wallet address'),
          ),
        );
      }
    }
  }

  void showSuccess() {
    setState(() => _showSuccess = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _overlayController.reverse().then((_) {
          if (mounted) {
            setState(() => _showSuccess = false);
            widget.onSuccessShown(); // Notify parent to reset the flag
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.4,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            border: Border(
              left: BorderSide(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
          ),
          child: _showSuccess
              ? const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: Colors.green,
                      size: 46,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Successfully Minted!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text(
                        'Advertisement',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 32,
                      width: 80,
                      child: ElevatedButton(
                        onPressed: _handleGoPress,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: const Text('Go'),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
