import '../state/lan_chat_controller.dart';

class ChatProvider extends LanChatController {
  ChatProvider({required super.selfId, String? selfName})
    : super(selfName: selfName ?? 'Zebra');
}
