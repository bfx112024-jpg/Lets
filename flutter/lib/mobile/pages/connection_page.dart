import 'dart:async';

import 'package:auto_size_text_field/auto_size_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/mobile/widgets/dialog.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/widgets/connection_page_title.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import '../../common.dart';
import '../../common/widgets/dialog.dart';
import '../../common/widgets/peer_tab_page.dart';
import '../../common/widgets/autocomplete.dart';
import '../../consts.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../../models/server_model.dart';
import 'home_page.dart';

/// Connection page for connecting to a remote peer.
class ConnectionPage extends StatefulWidget implements PageShape {
  ConnectionPage({Key? key, required this.appBarActions}) : super(key: key);

  @override
  final icon = const Icon(Icons.connected_tv);

  @override
  final title = translate("Connection");

  @override
  final List<Widget> appBarActions;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

/// State for the connection page.
class _ConnectionPageState extends State<ConnectionPage> {
  /// Controller for the id input bar.
  Timer? _updateTimer;
  final _idController = IDTextEditingController();
  final RxBool _idEmpty = true.obs;

  final FocusNode _idFocusNode = FocusNode();
  final TextEditingController _idEditingController = TextEditingController();

  final AllPeersLoader _allPeersLoader = AllPeersLoader();

  StreamSubscription? _uniLinksSubscription;

  // https://github.com/flutter/flutter/issues/157244
  Iterable<Peer> _autocompleteOpts = [];

  _ConnectionPageState() {
    if (!isWeb) _uniLinksSubscription = listenUniLinks();
    _idController.addListener(() {
      _idEmpty.value = _idController.text.isEmpty;
    });
    Get.put<IDTextEditingController>(_idController);
  }

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(const Duration(seconds: 3), () async {
      await gFFI.serverModel.fetchID();
    });
    gFFI.serverModel.checkAndroidPermission();

    _allPeersLoader.init(setState);
    _idFocusNode.addListener(onFocusChanged);
    if (_idController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final lastRemoteId = await bind.mainGetLastRemoteId();
        if (lastRemoteId != _idController.id) {
          setState(() {
            _idController.id = lastRemoteId;
          });
        }
      });
    }
    Get.put<TextEditingController>(_idEditingController);
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<FfiModel>(context);
    //checkService();
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(
        builder: (context, serverModel, child) => SingleChildScrollView(
          controller: gFFI.serverModel.controller,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                gFFI.serverModel.isStart
                    ? ServerInfo()
                    : ServiceNotRunningNotification(),
                const ConnectionManager(),
                const PermissionChecker(),
                SizedBox.fromSize(size: const Size(0, 15.0)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Callback for the connect button.
  /// Connects to the selected peer.
  void onConnect() {
    var id = _idController.id;
    connect(context, id);
  }

  void onFocusChanged() {
    _idEmpty.value = _idEditingController.text.isEmpty;
    if (_idFocusNode.hasFocus) {
      if (_allPeersLoader.needLoad) {
        _allPeersLoader.getAllPeers();
      }

      final textLength = _idEditingController.value.text.length;
      // Select all to facilitate removing text, just following the behavior of address input of chrome.
      _idEditingController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: textLength,
      );
    }
  }

  /// UI for software update.
  /// If _updateUrl] is not empty, shows a button to update the software.
  Widget _buildUpdateUI(String updateUrl) {
    return updateUrl.isEmpty
        ? const SizedBox(height: 0)
        : InkWell(
            onTap: () async {
              final url = 'https://rustdesk.com/download';
              // https://pub.dev/packages/url_launcher#configuration
              // https://developer.android.com/training/package-visibility/use-cases#open-urls-custom-tabs
              //
              // `await launchUrl(Uri.parse(url))` can also run if skip
              // 1. The following check
              // 2. `<action android:name="android.support.customtabs.action.CustomTabsService" />` in AndroidManifest.xml
              //
              // But it is better to add the check.
              await launchUrl(Uri.parse(url));
            },
            child: Container(
              alignment: AlignmentDirectional.center,
              width: double.infinity,
              color: Colors.pinkAccent,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                translate('Download new version'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
  }

  /// UI for the remote ID TextField.
  /// Search for a peer and connect to it if the id exists.
  Widget _buildRemoteIDTextField() {
    final w = SizedBox(
      height: 84,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Ink(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.all(Radius.circular(13)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  padding: const EdgeInsets.only(left: 16, right: 16),
                  child: RawAutocomplete<Peer>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text == '') {
                        _autocompleteOpts = const Iterable<Peer>.empty();
                      } else if (_allPeersLoader.peers.isEmpty &&
                          !_allPeersLoader.isPeersLoaded) {
                        Peer emptyPeer = Peer(
                          id: '',
                          username: '',
                          hostname: '',
                          alias: '',
                          platform: '',
                          tags: [],
                          hash: '',
                          password: '',
                          forceAlwaysRelay: false,
                          rdpPort: '',
                          rdpUsername: '',
                          loginName: '',
                          device_group_name: '',
                        );
                        _autocompleteOpts = [emptyPeer];
                      } else {
                        String textWithoutSpaces =
                            textEditingValue.text.replaceAll(" ", "");
                        if (int.tryParse(textWithoutSpaces) != null) {
                          textEditingValue = TextEditingValue(
                            text: textWithoutSpaces,
                            selection: textEditingValue.selection,
                          );
                        }
                        String textToFind = textEditingValue.text.toLowerCase();

                        _autocompleteOpts = _allPeersLoader.peers
                            .where(
                              (peer) =>
                                  peer.id.toLowerCase().contains(textToFind) ||
                                  peer.username.toLowerCase().contains(
                                        textToFind,
                                      ) ||
                                  peer.hostname.toLowerCase().contains(
                                        textToFind,
                                      ) ||
                                  peer.alias.toLowerCase().contains(textToFind),
                            )
                            .toList();
                      }
                      return _autocompleteOpts;
                    },
                    focusNode: _idFocusNode,
                    textEditingController: _idEditingController,
                    fieldViewBuilder: (
                      BuildContext context,
                      TextEditingController fieldTextEditingController,
                      FocusNode fieldFocusNode,
                      VoidCallback onFieldSubmitted,
                    ) {
                      updateTextAndPreserveSelection(
                        fieldTextEditingController,
                        _idController.text,
                      );
                      return AutoSizeTextField(
                        controller: fieldTextEditingController,
                        focusNode: fieldFocusNode,
                        minFontSize: 18,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.visiblePassword,
                        // keyboardType: TextInputType.number,
                        onChanged: (String text) {
                          _idController.id = text;
                        },
                        style: const TextStyle(
                          fontFamily: 'WorkSans',
                          fontWeight: FontWeight.bold,
                          fontSize: 30,
                          color: MyTheme.idColor,
                        ),
                        decoration: InputDecoration(
                          labelText: translate('Remote ID'),
                          // hintText: 'Enter your remote ID',
                          border: InputBorder.none,
                          helperStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: MyTheme.darkGray,
                          ),
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            letterSpacing: 0.2,
                            color: MyTheme.darkGray,
                          ),
                        ),
                        inputFormatters: [IDTextInputFormatter()],
                        onSubmitted: (_) {
                          onConnect();
                        },
                      );
                    },
                    onSelected: (option) {
                      setState(() {
                        _idController.id = option.id;
                        FocusScope.of(context).unfocus();
                      });
                    },
                    optionsViewBuilder: (
                      BuildContext context,
                      AutocompleteOnSelected<Peer> onSelected,
                      Iterable<Peer> options,
                    ) {
                      options = _autocompleteOpts;
                      double maxHeight = options.length * 50;
                      if (options.length == 1) {
                        maxHeight = 52;
                      } else if (options.length == 3) {
                        maxHeight = 146;
                      } else if (options.length == 4) {
                        maxHeight = 193;
                      }
                      maxHeight = maxHeight.clamp(0, 200);
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Container(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 5,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: Material(
                              elevation: 4,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: maxHeight,
                                  maxWidth: 320,
                                ),
                                child: _allPeersLoader.peers.isEmpty &&
                                        !_allPeersLoader.isPeersLoaded
                                    ? Container(
                                        height: 80,
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                    : ListView(
                                        padding: EdgeInsets.only(top: 5),
                                        children: options
                                            .map(
                                              (peer) => AutocompletePeerTile(
                                                onSelect: () =>
                                                    onSelected(peer),
                                                peer: peer,
                                              ),
                                            )
                                            .toList(),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Obx(
                () => Offstage(
                  offstage: _idEmpty.value,
                  child: IconButton(
                    onPressed: () {
                      setState(() {
                        _idController.clear();
                      });
                    },
                    icon: Icon(Icons.clear, color: MyTheme.darkGray),
                  ),
                ),
              ),
              SizedBox(
                width: 60,
                height: 60,
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_forward,
                    color: MyTheme.darkGray,
                    size: 45,
                  ),
                  onPressed: onConnect,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final child = Column(
      children: [
        if (isWebDesktop)
          getConnectionPageTitle(
            context,
            true,
          ).marginOnly(bottom: 10, top: 15, left: 12),
        w,
      ],
    );
    return Align(
      alignment: Alignment.topCenter,
      child: Container(constraints: kMobilePageConstraints, child: child),
    );
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    _idController.dispose();
    _updateTimer?.cancel();
    _idFocusNode.removeListener(onFocusChanged);
    _allPeersLoader.clear();
    _idFocusNode.dispose();
    _idEditingController.dispose();
    if (Get.isRegistered<IDTextEditingController>()) {
      Get.delete<IDTextEditingController>();
    }
    if (Get.isRegistered<TextEditingController>()) {
      Get.delete<TextEditingController>();
    }
    super.dispose();
  }
}

void checkService() async {
  gFFI.invokeMethod("check_service");
  // for Android 10/11, request MANAGE_EXTERNAL_STORAGE permission from system setting page
  if (AndroidPermissionManager.isWaitingFile() && !gFFI.serverModel.fileOk) {
    AndroidPermissionManager.complete(
      kManageExternalStorage,
      await AndroidPermissionManager.check(kManageExternalStorage),
    );
    debugPrint("file permission finished");
  }
}

class ServiceNotRunningNotification extends StatelessWidget {
  ServiceNotRunningNotification({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    serverModel.tradeSupportActivate();
    return PaddingCard(
      title: translate("Service is not running"),
      titleIcon: const Icon(Icons.warning_amber_sharp, color: Colors.redAccent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            translate("android_start_service_tip"),
            style: const TextStyle(fontSize: 12, color: MyTheme.darkGray),
          ).marginOnly(bottom: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow),
            onPressed: () {
              serverModel.toggleService();
            },
            label: Text(translate("Start service")),
          ),
        ],
      ),
    );
  }
}

class ServerInfo extends StatelessWidget {
  final model = gFFI.serverModel;
  final emptyController = TextEditingController(text: "-");

  ServerInfo({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);

    const Color colorPositive = Colors.green;
    const Color colorNegative = Colors.red;
    const double iconMarginRight = 15;
    const double iconSize = 24;
    const TextStyle textStyleHeading = TextStyle(
      fontSize: 16.0,
      fontWeight: FontWeight.bold,
      color: Colors.grey,
    );
    const TextStyle textStyleValue = TextStyle(
      fontSize: 25.0,
      fontWeight: FontWeight.bold,
    );

    void copyToClipboard(String value) {
      Clipboard.setData(ClipboardData(text: value));
      showToast(translate('Copied'));
    }

    Widget ConnectionStateNotification() {
      if (serverModel.connectStatus == -1) {
        return Row(
          children: [
            const Icon(
              Icons.warning_amber_sharp,
              color: colorNegative,
              size: iconSize,
            ).marginOnly(right: iconMarginRight),
            Expanded(child: Text(translate('not_ready_status'))),
          ],
        );
      } else if (serverModel.connectStatus == 0) {
        return Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(),
            ).marginOnly(left: 4, right: iconMarginRight),
            Expanded(child: Text(translate('connecting_status'))),
          ],
        );
      } else {
        return Row(
          children: [
            const Icon(
              Icons.check,
              color: colorPositive,
              size: iconSize,
            ).marginOnly(right: iconMarginRight),
            Expanded(child: Text(translate('Ready'))),
          ],
        );
      }
    }

    final showOneTime = serverModel.approveMode != 'click' &&
        serverModel.verificationMethod != kUsePermanentPassword;
    return PaddingCard(
      title: translate('Your Device'),
      child: Column(
        // ID
        children: [
          Row(
            children: [
              const Icon(
                Icons.perm_identity,
                color: Colors.grey,
                size: iconSize,
              ).marginOnly(right: iconMarginRight),
              Text(translate('ID'), style: textStyleHeading),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(model.serverId.value.text, style: textStyleValue),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.copy_outlined),
                onPressed: () {
                  copyToClipboard(model.serverId.value.text.trim());
                },
              ),
            ],
          ).marginOnly(left: 39, bottom: 10),
          // Password
          Row(
            children: [
              const Icon(
                Icons.lock_outline,
                color: Colors.grey,
                size: iconSize,
              ).marginOnly(right: iconMarginRight),
              Text(translate('One-time Password'), style: textStyleHeading),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                !showOneTime ? '-' : model.serverPasswd.value.text,
                style: textStyleValue,
              ),
              !showOneTime
                  ? SizedBox.shrink()
                  : Row(
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.refresh),
                          onPressed: () => bind.mainUpdateTemporaryPassword(),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.copy_outlined),
                          onPressed: () {
                            copyToClipboard(
                              model.serverPasswd.value.text.trim(),
                            );
                          },
                        ),
                      ],
                    ),
            ],
          ).marginOnly(left: 40, bottom: 15),
          ConnectionStateNotification(),
        ],
      ),
    );
  }
}

class PermissionChecker extends StatefulWidget {
  const PermissionChecker({Key? key}) : super(key: key);

  @override
  State<PermissionChecker> createState() => _PermissionCheckerState();
}

class _PermissionCheckerState extends State<PermissionChecker> {
  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    final hasAudioPermission = androidVersion >= 30;
    return PaddingCard(
      title: translate("Permissions"),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          serverModel.mediaOk
              ? ElevatedButton.icon(
                  style: ButtonStyle(
                    backgroundColor: MaterialStateProperty.all(Colors.red),
                  ),
                  icon: const Icon(Icons.stop),
                  onPressed: serverModel.toggleService,
                  label: Text(translate("Stop service")),
                ).marginOnly(bottom: 8)
              : SizedBox.shrink(),
          PermissionRow(
            translate("Screen Capture"),
            serverModel.mediaOk,
            serverModel.toggleService,
          ),
          // PermissionRow(
          //   translate("Input Control"),
          //   serverModel.inputOk,
          //   serverModel.toggleInput,
          // ),
          // PermissionRow(
          //   translate("Transfer file"),
          //   serverModel.fileOk,
          //   serverModel.toggleFile,
          // ),
          // hasAudioPermission
          //     ? PermissionRow(
          //         translate("Audio Capture"),
          //         serverModel.audioOk,
          //         serverModel.toggleAudio,
          //       )
          //     : Row(
          //         children: [
          //           Icon(Icons.info_outline).marginOnly(right: 15),
          //           Expanded(
          //             child: Text(
          //               translate("android_version_audio_tip"),
          //               style: const TextStyle(color: MyTheme.darkGray),
          //             ),
          //           ),
          //         ],
          //       ),
          // PermissionRow(
          //   translate("Enable clipboard"),
          //   serverModel.clipboardOk,
          //   serverModel.toggleClipboard,
          // ),
        ],
      ),
    );
  }
}

class PermissionRow extends StatelessWidget {
  const PermissionRow(this.name, this.isOk, this.onPressed, {Key? key})
      : super(key: key);

  final String name;
  final bool isOk;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.all(0),
      title: Text(name),
      value: isOk,
      onChanged: (bool value) {
        onPressed();
      },
    );
  }
}

class ConnectionManager extends StatelessWidget {
  const ConnectionManager({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    return Column(
      children: serverModel.clients.map(
        (client) {
          client.authorized = true;
          return PaddingCard(
            title: translate(
              client.isFileTransfer ? "Transfer file" : "Share screen",
            ),
            titleIcon: client.isFileTransfer
                ? Icon(Icons.folder_outlined)
                : Icon(Icons.mobile_screen_share),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: ClientInfo(client)),
                    // Show chat button only if not file transfer
                    if (!client.isFileTransfer)
                      IconButton(
                        onPressed: () {
                          gFFI.chatModel.changeCurrentKey(
                            MessageKey(client.peerId, client.id),
                          );
                          final bar = navigationBarKey.currentWidget;
                          if (bar != null) {
                            bar as BottomNavigationBar;
                            bar.onTap!(1);
                          }
                        },
                        icon: unreadTopRightBuilder(
                          client.unreadChatMessageCount,
                        ),
                      ),
                  ],
                ),
                _buildDisconnectButton(client),
                if (client.incomingVoiceCall && !client.inVoiceCall)
                  ..._buildNewVoiceCallHint(context, serverModel, client),
              ],
            ),
          );
        },
      ).toList(),
    );
  }

  Widget _buildDisconnectButton(Client client) {
    final disconnectButton = ElevatedButton.icon(
      style: ButtonStyle(backgroundColor: MaterialStatePropertyAll(Colors.red)),
      icon: const Icon(Icons.close),
      onPressed: () {
        bind.cmCloseConnection(connId: client.id);
        gFFI.invokeMethod("cancel_notification", client.id);
      },
      label: Text(translate("Disconnect")),
    );
    final buttons = [disconnectButton];
    if (client.inVoiceCall) {
      buttons.insert(
        0,
        ElevatedButton.icon(
          style: ButtonStyle(
            backgroundColor: MaterialStatePropertyAll(Colors.red),
          ),
          icon: const Icon(Icons.phone),
          label: Text(translate("Stop")),
          onPressed: () {
            bind.cmCloseVoiceCall(id: client.id);
            gFFI.invokeMethod("cancel_notification", client.id);
          },
        ),
      );
    }

    if (buttons.length == 1) {
      return Container(
        alignment: Alignment.centerRight,
        child: disconnectButton,
      );
    } else {
      return Row(
        children: buttons,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
      );
    }
  }

  Widget _buildNewConnectionHint(ServerModel serverModel, Client client) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          child: Text(translate("Dismiss")),
          onPressed: () {
            serverModel.sendLoginResponse(client, false);
          },
        ).marginOnly(right: 15),
        if (serverModel.approveMode != 'password')
          ElevatedButton.icon(
            icon: const Icon(Icons.check),
            label: Text(translate("Accept")),
            onPressed: () {
              serverModel.sendLoginResponse(client, true);
            },
          ),
      ],
    );
  }

  List<Widget> _buildNewVoiceCallHint(
    BuildContext context,
    ServerModel serverModel,
    Client client,
  ) {
    return [
      Text(
        translate("android_new_voice_call_tip"),
        style: Theme.of(context).textTheme.bodyMedium,
      ).marginOnly(bottom: 5),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            child: Text(translate("Dismiss")),
            onPressed: () {
              serverModel.handleVoiceCall(client, false);
            },
          ).marginOnly(right: 15),
          if (serverModel.approveMode != 'password')
            ElevatedButton.icon(
              icon: const Icon(Icons.check),
              label: Text(translate("Accept")),
              onPressed: () {
                serverModel.handleVoiceCall(client, true);
              },
            ),
        ],
      ),
    ];
  }
}

class PaddingCard extends StatelessWidget {
  const PaddingCard({Key? key, required this.child, this.title, this.titleIcon})
      : super(key: key);

  final String? title;
  final Icon? titleIcon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final children = [child];
    if (title != null) {
      children.insert(
        0,
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 5, 0, 8),
          child: Row(
            children: [
              titleIcon?.marginOnly(right: 10) ?? const SizedBox.shrink(),
              Expanded(
                child: Text(
                  title!,
                  style: Theme.of(context).textTheme.titleLarge?.merge(
                        TextStyle(fontWeight: FontWeight.bold),
                      ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return SizedBox(
      width: double.maxFinite,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        margin: const EdgeInsets.fromLTRB(12.0, 10.0, 12.0, 0),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15.0, horizontal: 20.0),
          child: Column(children: children),
        ),
      ),
    );
  }
}

class ClientInfo extends StatelessWidget {
  final Client client;
  ClientInfo(this.client);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: -1,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: CircleAvatar(
                    backgroundColor: str2color(
                      client.name,
                      Theme.of(context).brightness == Brightness.light
                          ? 255
                          : 150,
                    ),
                    child: Text(client.name[0]),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(client.name, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Text(client.peerId, style: const TextStyle(fontSize: 10)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

void androidChannelInit() {
  gFFI.setMethodCallHandler((method, arguments) {
    debugPrint("flutter got android msg,$method,$arguments");
    try {
      switch (method) {
        case "start_capture":
          {
            gFFI.dialogManager.dismissAll();
            gFFI.serverModel.updateClientState();
            break;
          }
        case "on_state_changed":
          {
            var name = arguments["name"] as String;
            var value = arguments["value"] as String == "true";
            debugPrint("from jvm:on_state_changed,$name:$value");
            gFFI.serverModel.changeStatue(name, value);
            break;
          }
        case "on_android_permission_result":
          {
            var type = arguments["type"] as String;
            var result = arguments["result"] as bool;
            AndroidPermissionManager.complete(type, result);
            break;
          }
        case "on_media_projection_canceled":
          {
            gFFI.serverModel.stopService();
            break;
          }
        case "msgbox":
          {
            var type = arguments["type"] as String;
            var title = arguments["title"] as String;
            var text = arguments["text"] as String;
            var link = (arguments["link"] ?? '') as String;
            msgBox(gFFI.sessionId, type, title, text, link, gFFI.dialogManager);
            break;
          }
        case "stop_service":
          {
            print(
              "stop_service by kotlin, isStart:${gFFI.serverModel.isStart}",
            );
            if (gFFI.serverModel.isStart) {
              gFFI.serverModel.stopService();
            }
            break;
          }
      }
    } catch (e) {
      debugPrintStack(label: "MethodCallHandler err:$e");
    }
    return "";
  });
}
