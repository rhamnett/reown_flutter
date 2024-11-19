import 'dart:developer';

import 'package:fl_toast/fl_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:reown_appkit_example/services/deep_link_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
// import 'package:http/http.dart' as http;

import 'package:reown_appkit/reown_appkit.dart';

import 'package:reown_appkit_example/widgets/debug_drawer.dart';
import 'package:reown_appkit_example/utils/constants.dart';
import 'package:reown_appkit_example/services/siwe_service.dart';
import 'package:reown_appkit_example/widgets/logger_widget.dart';
import 'package:reown_appkit_example/widgets/session_widget.dart';
import 'package:reown_appkit_example/utils/dart_defines.dart';

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
  final overlay = OverlayController(const Duration(milliseconds: 200));
  late ReownAppKitModal _appKitModal;
  late SIWESampleWebService _siweTestService;
  late VideoPlayerController _videoController;
  bool _initialized = false;

  String? _pendingAction;

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
      _toggleOverlay();
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
    Uri link = Uri.parse('https://appkit-lab.reown.com/flutter_appkit_modal');
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
          // Implement your verifyMessage to authenticate the user after it.
          try {
            debugPrint('[SIWEConfig] verifyMessage()');
            final payload = args.toJson();
            final url = _pairingMetadata().url;
            final uri = Uri.parse(url);
            final result = await _siweTestService.verifyMessage(
              payload,
              domain: uri.authority,
            );
            return result['token'] != null;
          } catch (error) {
            debugPrint('[SIWEConfig] verifyMessage error: $error');
            // Fallback patch for testing purposes in case SIWE backend has issues
            final chainId = SIWEUtils.getChainIdFromMessage(args.message);
            final address = SIWEUtils.getAddressFromMessage(args.message);
            final cacaoSignature = args.cacao != null
                ? args.cacao!.s
                : CacaoSignature(
                    t: CacaoSignature.EIP191,
                    s: args.signature,
                  );
            return await SIWEUtils.verifySignature(
              address,
              args.message,
              cacaoSignature,
              chainId,
              DartDefines.projectId,
            );
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
            final address = _appKitModal.session!.address!;
            final chainId = _appKitModal.session!.chainId;
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
        signOutOnNetworkChange: false,
        // nonceRefetchIntervalMs: 300000,
        // sessionRefetchIntervalMs: 300000,
      );

  void _initializeService(SharedPreferences prefs) async {
    final analyticsValue = prefs.getBool('appkit_analytics') ?? true;
    final emailWalletValue = prefs.getBool('appkit_email_wallet') ?? true;
    final siweAuthValue = prefs.getBool('appkit_siwe_auth') ?? true;

    // See https://docs.reown.com/appkit/flutter/core/custom-chains
    final testNetworks = ReownAppKitModalNetworks.test['eip155'] ?? [];
    ReownAppKitModalNetworks.addNetworks('eip155', testNetworks);

    try {
      _appKitModal = ReownAppKitModal(
        context: context,
        projectId: DartDefines.projectId,
        logLevel: LogLevel.error,
        metadata: _pairingMetadata(),
        siweConfig: _siweConfig(siweAuthValue),
        enableAnalytics: analyticsValue, // OPTIONAL - null by default
        featuresConfig: FeaturesConfig(
          email: emailWalletValue,
          socials: [
            // AppKitSocialOption.Farcaster,
            AppKitSocialOption.Apple,
            AppKitSocialOption.X,
            AppKitSocialOption.Discord
          ],
          showMainWallets: true, // OPTIONAL - true by default
        ),
        // requiredNamespaces: {},
        // optionalNamespaces: {},
        includedWalletIds: {
          'f71e9b2c658264f7c6dfe938bbf9d2a025acc7ba4245eea2356e2995b1fd24d3', // m1nty
          'c57ca95b47569778a828d19178114f4db188b89b763c899ba0be274e97267d96', // Metamask
        },
        // featuredWalletIds: {
        //   //m1nty
        //   'f71e9b2c658264f7c6dfe938bbf9d2a025acc7ba4245eea2356e2995b1fd24d3', // m1nty
        //   // 'fd20dc426fb37566d803205b19bbc1d4096b248ac04548e3cfb6b3a38bd033aa', // Coinbase
        //   // '18450873727504ae9315a084fa7624b5297d2fe5880f0982979c17345a138277', // Kraken Wallet
        //   'c57ca95b47569778a828d19178114f4db188b89b763c899ba0be274e97267d96', // Metamask
        //   // '1ae92b26df02f0abca6304df07debccd18262fdf5fe82daa81593582dac9a369', // Rainbow
        //   // 'c03dfee351b6fcc421b4494ea33b9d4b92a984f87aa76d1663bb28705e95034a', // Uniswap
        //   // '38f5d18bd8522c244bdd70cb4a68e0e718865155811c043f052fb9f1c51de662', // Bitget
        // },
        // excludedWalletIds: {
        //   'fd20dc426fb37566d803205b19bbc1d4096b248ac04548e3cfb6b3a38bd033aa', // Coinbase
        // },
        // MORE WALLETS https://explorer.walletconnect.com/?type=wallet&chains=eip155%3A1
      );
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
    _appKitModal.appKit!.core.addLogListener(_logListener);
    //
    await _appKitModal.init();

    DeepLinkHandler.init(_appKitModal);
    DeepLinkHandler.checkInitialLink();

    setState(() {});
  }

  void _logListener(event) {
    if ('${event.level}' == 'Level.debug' ||
        '${event.level}' == 'Level.error') {
      // TODO send to mixpanel
      log('${event.message}');
    } else {
      debugPrint('${event.message}');
    }
  }

  @override
  void dispose() {
    _videoController.dispose();
    //
    _appKitModal.appKit!.core.removeLogListener(_logListener);
    _appKitModal.appKit!.core.relayClient.onRelayClientConnect.unsubscribe(
      _onRelayClientConnect,
    );
    _appKitModal.appKit!.core.relayClient.onRelayClientError.unsubscribe(
      _onRelayClientError,
    );
    _appKitModal.appKit!.core.relayClient.onRelayClientDisconnect.unsubscribe(
      _onRelayClientDisconnect,
    );
    //
    _appKitModal.onModalConnect.unsubscribe(_onModalConnect);
    _appKitModal.onModalUpdate.unsubscribe(_onModalUpdate);
    _appKitModal.onModalNetworkChange.unsubscribe(_onModalNetworkChange);
    _appKitModal.onModalDisconnect.unsubscribe(_onModalDisconnect);
    _appKitModal.onModalError.unsubscribe(_onModalError);
    //
    _appKitModal.onSessionExpireEvent.unsubscribe(_onSessionExpired);
    _appKitModal.onSessionUpdateEvent.unsubscribe(_onSessionUpdate);
    _appKitModal.onSessionEventEvent.unsubscribe(_onSessionEvent);
    //
    super.dispose();
  }

  void _handlePendingAction() {
    if (_pendingAction != null && _appKitModal.isConnected) {
      final address = _appKitModal.session!.address!;

      switch (_pendingAction) {
        case 'mint':
          mintToken(address);
          break;
        case 'loyalty':
          getLoyalty(address);
          break;
      }

      // Clear pending action after handling
      setState(() => _pendingAction = null);
    }
  }

  void mintToken(String address) async {
    // Implement token minting logic here
    debugPrint('Minting token for address: $address');
  }

  void getLoyalty(String address) async {
    // Implement get loyalty logic here
    debugPrint('Getting loyalty offers for address: $address');
  }

  void _onModalConnect(ModalConnect? event) async {
    setState(() {});
    debugPrint('[ExampleApp] _onModalConnect ${event?.session.toJson()}');

    // notify m1nty API that a wallet has connected
    // _m1ntyApi.notifyWalletConnected(event?.session, DateTime.now());

    _handlePendingAction();
  }

  void _onModalUpdate(ModalConnect? event) {
    setState(() {});
  }

  void _onModalNetworkChange(ModalNetworkChange? event) {
    debugPrint('[ExampleApp] _onModalNetworkChange ${event?.toString()}');
    setState(() {});
  }

  void _onModalDisconnect(ModalDisconnect? event) {
    debugPrint('[ExampleApp] _onModalDisconnect ${event?.toString()}');
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

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return SizedBox.shrink();
    }
    return Scaffold(
      backgroundColor: ReownAppKitModalTheme.colorsOf(context).background125,
      appBar: AppBar(
        elevation: 0.0,
        title: const Text(StringConstants.pageTitle),
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
                      child: Image.asset(
                        'assets/logo.png',
                        height: 100,
                        fit: BoxFit.contain,
                      ),
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
                    _ConnectedView(appKit: _appKitModal),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // AppKitModalNetworkSelectButton(
        //   appKit: appKit,
        //   // UNCOMMENT TO USE A CUSTOM BUTTON
        //   // custom: ElevatedButton(
        //   //   onPressed: () {
        //   //     appKit.openNetworksView();
        //   //   },
        //   //   child: Text(appKit.selectedChain?.name ?? 'OPEN CHAINS'),
        //   // ),
        // ),
        // const SizedBox.square(dimension: 6.0),
        AppKitModalConnectButton(
          appKit: appKit,
          // UNCOMMENT TO USE A CUSTOM BUTTON
          // TO HIDE AppKitModalConnectButton BUT STILL RENDER IT (NEEDED) JUST USE SizedBox.shrink()
          custom: ElevatedButton(
            onPressed: () {
              if (!appKit.isConnected) {
                (context.findAncestorStateOfType<_MyHomePageState>())
                    ?._pendingAction = 'loyalty';
                appKit.openModalView(ReownAppKitModalMainWalletsPage());
              } else {
                final address = appKit.session!.address!;
                (context.findAncestorStateOfType<_MyHomePageState>())
                    ?.getLoyalty(address);
              }
            },
            child: appKit.isConnected
                ? Text('${appKit.session!.address!.substring(0, 7)}...')
                : const Text('Get loyalty offers'),
          ),
        ),
      ],
    );
  }
}

class _ConnectedView extends StatelessWidget {
  const _ConnectedView({required this.appKit});
  final ReownAppKitModal appKit;

  @override
  Widget build(BuildContext context) {
    if (!appKit.isConnected) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AppKitModalAccountButton(
          appKit: appKit,
          // custom: ValueListenableBuilder<String>(
          //   valueListenable: appKit.balanceNotifier,
          //   builder: (_, balance, __) {
          //     return ElevatedButton(
          //       onPressed: () {
          //         appKit.openModalView();
          //       },
          //       child: Text(balance),
          //     );
          //   },
          // ),
        ),
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
        const SizedBox.square(dimension: 30.0),
        // SessionWidget(appKit: appKit),
        const SizedBox.square(dimension: 12.0),
      ],
    );
  }
}

class _VideoControls extends StatefulWidget {
  const _VideoControls({
    required this.controller,
    required this.appKit,
  });

  final VideoPlayerController controller;
  final ReownAppKitModal appKit;

  @override
  State<_VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<_VideoControls>
    with SingleTickerProviderStateMixin {
  late AnimationController _overlayController;
  late Animation<Offset> _slideAnimation;
  // final TextEditingController _emailController = TextEditingController();

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
  void dispose() {
    // _emailController.dispose();
    _overlayController.dispose();
    super.dispose();
  }

  Future<void> _handleGoPress() async {
    final appKit = widget.appKit;
    if (!appKit.isConnected) {
      (context.findAncestorStateOfType<_MyHomePageState>())?._pendingAction =
          'mint';
      appKit.openModalView(ReownAppKitModalMainWalletsPage());
    } else {
      final address = appKit.session!.address!;
      (context.findAncestorStateOfType<_MyHomePageState>())?.mintToken(address);
    }
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
          child: Column(
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
              // Padding(
              //   padding: const EdgeInsets.symmetric(horizontal: 8.0),
              //   child: SizedBox(
              //     height: 32,
              //     child: TextField(
              //       controller: _emailController,
              //       style: const TextStyle(color: Colors.white),
              //       decoration: InputDecoration(
              //         hintText: 'Enter email',
              //         hintStyle:
              //             TextStyle(color: Colors.white.withOpacity(0.5)),
              //         contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              //         border: OutlineInputBorder(
              //           borderSide:
              //               BorderSide(color: Colors.white.withOpacity(0.3)),
              //         ),
              //         enabledBorder: OutlineInputBorder(
              //           borderSide:
              //               BorderSide(color: Colors.white.withOpacity(0.3)),
              //         ),
              //       ),
              //     ),
              //   ),
              // ),
              // const SizedBox(height: 8),
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
