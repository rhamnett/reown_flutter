import 'dart:convert';

import 'package:fl_toast/fl_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:reown_appkit_example/utils/styles.dart';

import 'package:reown_appkit/reown_appkit.dart';

import 'package:reown_appkit_example/utils/constants.dart';
import 'package:reown_appkit_example/services/eip155_service.dart';
import 'package:reown_appkit_example/widgets/method_dialog.dart';

class SessionWidget extends StatefulWidget {
  const SessionWidget({super.key, required this.appKit});

  final ReownAppKitModal appKit;

  @override
  SessionWidgetState createState() => SessionWidgetState();
}

class SessionWidgetState extends State<SessionWidget> {
  @override
  Widget build(BuildContext context) {
    final session = widget.appKit.session!;
    String iconImage = '';
    if ((session.peer?.metadata.icons ?? []).isNotEmpty) {
      iconImage = session.peer?.metadata.icons.first ?? '';
    }
    final List<Widget> children = [
      const SizedBox(height: 8.0),
      Row(
        children: [
          if (iconImage.isNotEmpty)
            Row(
              children: [
                CircleAvatar(
                  radius: 18.0,
                  backgroundImage: NetworkImage(iconImage),
                ),
                const SizedBox(width: 8.0),
              ],
            ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    session.connectedWalletName ?? '',
                    style: ReownAppKitModalTheme.getDataOf(context)
                        .textStyles
                        .paragraph600
                        .copyWith(
                          color: ReownAppKitModalTheme.colorsOf(context)
                              .foreground100,
                        ),
                  ),
                ),
                Visibility(
                  visible: !session.sessionService.isMagic,
                  child: IconButton(
                    onPressed: () {
                      widget.appKit.launchConnectedWallet();
                    },
                    icon: const Icon(Icons.open_in_new),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 8.0),
      // TOPIC LABEL
      Visibility(
        visible: session.topic != null,
        child: Column(
          children: [
            Text(
              StringConstants.sessionTopic,
              style: ReownAppKitModalTheme.getDataOf(context)
                  .textStyles
                  .small600
                  .copyWith(
                    color:
                        ReownAppKitModalTheme.colorsOf(context).foreground100,
                  ),
            ),
            Text(
              '${session.topic}',
              style: ReownAppKitModalTheme.getDataOf(context)
                  .textStyles
                  .small400
                  .copyWith(
                    color:
                        ReownAppKitModalTheme.colorsOf(context).foreground100,
                  ),
            ),
          ],
        ),
      ),
      Column(
        children: _buildSupportedChainsWidget(),
      ),
      const SizedBox(height: StyleConstants.linear8),
    ];

    // Get current active account
    final accounts = session.getAccounts() ?? [];
    final chainId = widget.appKit.selectedChain?.chainId ?? '';
    final namespace = ReownAppKitModalNetworks.getNamespaceForChainId(chainId);
    final chainsNamespaces = NamespaceUtils.getChainsFromAccounts(accounts);
    if (chainsNamespaces.contains('$namespace:$chainId')) {
      final account = accounts.firstWhere(
        (account) => account.contains('$namespace:$chainId'),
      );
      children.add(_buildAccountWidget(account));
    }
    children.add(
      Column(
        children: [
          const SizedBox.square(dimension: 8.0),
          Text(
            'Stored session:',
            style: ReownAppKitModalTheme.getDataOf(context)
                .textStyles
                .small600
                .copyWith(
                  color: ReownAppKitModalTheme.colorsOf(context).foreground100,
                ),
          ),
          InkWell(
            onTap: () => Clipboard.setData(
              ClipboardData(
                text: jsonEncode(widget.appKit.session?.toMap()),
              ),
            ).then(
              (_) => showPlatformToast(
                child: const Text(StringConstants.copiedToClipboard),
                context: context,
              ),
            ),
            child: Text(
              const JsonEncoder.withIndent('     ')
                  .convert(widget.appKit.session?.toMap()),
              style: ReownAppKitModalTheme.getDataOf(context)
                  .textStyles
                  .small400
                  .copyWith(
                    color:
                        ReownAppKitModalTheme.colorsOf(context).foreground100,
                  ),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0),
      child: Column(children: children),
    );
  }

  Widget _buildAccountWidget(String account) {
    final List<Widget> children = [
      Text(
        widget.appKit.selectedChain?.name ?? 'Unsupported chain',
        style: ReownAppKitModalTheme.getDataOf(context)
            .textStyles
            .title600
            .copyWith(
              color: ReownAppKitModalTheme.colorsOf(context).foreground100,
            ),
      ),
      const SizedBox(height: StyleConstants.linear8),
      Text(
        NamespaceUtils.getAccount(account),
        style: ReownAppKitModalTheme.getDataOf(context)
            .textStyles
            .small400
            .copyWith(
              color: ReownAppKitModalTheme.colorsOf(context).foreground100,
            ),
      ),
    ];

    children.addAll([
      const SizedBox(height: StyleConstants.linear8),
      Text(
        StringConstants.methods,
        style: ReownAppKitModalTheme.getDataOf(context)
            .textStyles
            .paragraph600
            .copyWith(
              color: ReownAppKitModalTheme.colorsOf(context).foreground100,
            ),
      ),
    ]);
    children.addAll(_buildChainMethodButtons(account));

    children.addAll([
      const SizedBox(height: StyleConstants.linear8),
      Text(
        StringConstants.events,
        style: ReownAppKitModalTheme.getDataOf(context)
            .textStyles
            .paragraph600
            .copyWith(
              color: ReownAppKitModalTheme.colorsOf(context).foreground100,
            ),
      ),
    ]);
    children.add(_buildChainEventsTiles());

    return Container(
      padding: const EdgeInsets.all(StyleConstants.linear8),
      margin: const EdgeInsets.symmetric(vertical: StyleConstants.linear8),
      decoration: BoxDecoration(
        border: Border.all(
            color: ReownAppKitModalTheme.colorsOf(context).accent100),
        borderRadius: const BorderRadius.all(
          Radius.circular(StyleConstants.linear8),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  List<Widget> _buildChainMethodButtons(
    String address,
  ) {
    // Add Methods
    final approvedMethods = widget.appKit.getApprovedMethods() ?? <String>[];
    if (approvedMethods.isEmpty) {
      return [
        Text(
          'No methods approved',
          style: ReownAppKitModalTheme.getDataOf(context)
              .textStyles
              .small400
              .copyWith(
                color: ReownAppKitModalTheme.colorsOf(context).foreground100,
              ),
        )
      ];
    }
    final usableMethods = EIP155UIMethods.values.map((e) => e.name).toList();
    //
    final List<Widget> children = [];
    for (final method in approvedMethods) {
      final implemented = usableMethods.contains(method);
      children.add(
        Container(
          height: StyleConstants.linear40,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: StyleConstants.linear8),
          child: ElevatedButton(
            onPressed: implemented
                ? () async {
                    widget.appKit.launchConnectedWallet();
                    final future = callChainMethod(EIP155.methodFromName(
                      method,
                    ));
                    MethodDialog.show(context, method, future);
                  }
                : null,
            style: buttonStyle(context),
            child: Text(method),
          ),
        ),
      );
    }

    children.add(const Divider());
    final onSepolia = widget.appKit.selectedChain?.chainId == '11155111';
    if (!onSepolia) {
      children.add(
        const Text(
          'Test USDT Contract on Ethereum \nor switch to Sepolia to try a test Contract',
          textAlign: TextAlign.center,
        ),
      );
    } else {
      children.add(
        const Text(
          'Test AAVE Token Contract on Sepolia \nor switch to Ethereum to try USDT',
          textAlign: TextAlign.center,
        ),
      );
    }
    final onMainnet = widget.appKit.selectedChain?.chainId == '1';

    children.addAll([
      Container(
        height: StyleConstants.linear40,
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: StyleConstants.linear8),
        child: ElevatedButton(
          onPressed: onSepolia
              ? () async {
                  final future = EIP155.callTestSmartContract(
                    appKitModal: widget.appKit,
                    action: 'read',
                  );
                  MethodDialog.show(
                    context,
                    'Test Contract (Read)',
                    future,
                  );
                }
              : onMainnet
                  ? () async {
                      final future = EIP155.callUSDTSmartContract(
                        appKitModal: widget.appKit,
                        action: 'read',
                      );
                      MethodDialog.show(
                        context,
                        'Test Contract (Read)',
                        future,
                      );
                    }
                  : null,
          style: buttonStyle(context),
          child: onMainnet
              ? const Text('USDT Contract (Read)')
              : const Text('AAVE Contract (Read)'),
        ),
      ),
      Container(
        height: StyleConstants.linear40,
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: StyleConstants.linear8),
        child: ElevatedButton(
          onPressed: onSepolia
              ? () async {
                  widget.appKit.launchConnectedWallet();
                  final future = EIP155.callTestSmartContract(
                    appKitModal: widget.appKit,
                    action: 'write',
                  );
                  MethodDialog.show(context, 'Test Contract (Write)', future);
                }
              : onMainnet
                  ? () async {
                      widget.appKit.launchConnectedWallet();
                      final future = EIP155.callUSDTSmartContract(
                        appKitModal: widget.appKit,
                        action: 'write',
                      );
                      MethodDialog.show(
                          context, 'Test Contract (Write)', future);
                    }
                  : null,
          style: buttonStyle(context),
          child: onMainnet
              ? const Text('USDT Contract (Write)')
              : const Text('AAVE Contract (Write)'),
        ),
      ),
    ]);

    return children;
  }

  List<Widget> _buildSupportedChainsWidget() {
    List<Widget> children = [];
    children.addAll(
      [
        const SizedBox(height: StyleConstants.linear8),
        Text(
          'Session chains:',
          style: ReownAppKitModalTheme.getDataOf(context)
              .textStyles
              .small600
              .copyWith(
                color: ReownAppKitModalTheme.colorsOf(context).foreground100,
              ),
        ),
      ],
    );
    final approvedChains = widget.appKit.getApprovedChains() ?? <String>[];
    children.add(
      Text(
        approvedChains.join(', '),
        style: ReownAppKitModalTheme.getDataOf(context)
            .textStyles
            .small400
            .copyWith(
              color: ReownAppKitModalTheme.colorsOf(context).foreground100,
            ),
      ),
    );
    return children;
  }

  Widget _buildChainEventsTiles() {
    // Add Events
    final approvedEvents = widget.appKit.getApprovedEvents() ?? <String>[];
    if (approvedEvents.isEmpty) {
      return Text(
        'No events approved',
        style: ReownAppKitModalTheme.getDataOf(context)
            .textStyles
            .small400
            .copyWith(
              color: ReownAppKitModalTheme.colorsOf(context).foreground100,
            ),
      );
    }
    final List<Widget> children = [];
    for (final event in approvedEvents) {
      children.add(
        Container(
          margin: const EdgeInsets.symmetric(
            vertical: StyleConstants.linear8,
            horizontal: StyleConstants.linear8,
          ),
          padding: const EdgeInsets.all(StyleConstants.linear8),
          decoration: BoxDecoration(
            border: Border.all(
              color: ReownAppKitModalTheme.colorsOf(context).accent100,
            ),
            borderRadius: borderRadius(context),
          ),
          child: Text(
            event,
            style: ReownAppKitModalTheme.getDataOf(context)
                .textStyles
                .small400
                .copyWith(
                  color: ReownAppKitModalTheme.colorsOf(context).foreground100,
                ),
          ),
        ),
      );
    }

    return Wrap(
      children: children,
    );
  }

  Future<dynamic> callChainMethod(EIP155UIMethods method) {
    final session = widget.appKit.session!;
    return EIP155.callMethod(
      appKitModal: widget.appKit,
      topic: session.topic ?? '',
      method: method,
      chainId: widget.appKit.selectedChain!.chainId,
      address: session.address!,
    );
  }
}
