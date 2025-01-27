import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/key.dart';

class CustomCssPage extends StatefulWidget {
  const CustomCssPage({Key? key}) : super(key: key);

  @override
  CustomCssPageState createState() => CustomCssPageState();
}

class CustomCssPageState extends State<CustomCssPage> {
  final TextEditingController _customCssController = TextEditingController();

  Future<void> initData() async {
    final String css = await getCustomCss();
    setState(() {
      _customCssController.text = css;
    });
  }

  @override
  void initState() {
    super.initState();
    initData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('自定义CSS'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        children: [
          TextFormField(
            controller: _customCssController,
            expands: false,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: '输入 CSS 代码',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.tonal(
                onPressed: () {
                  // 从剪贴板获取，光标移到末尾
                  Clipboard.getData('text/plain').then((value) {
                    if (value != null) {
                      _customCssController.text = value.text!;
                      _customCssController.selection =
                          TextSelection.fromPosition(
                              TextPosition(offset: value.text!.length));
                    }
                  });
                },
                child: const Text('粘贴'),
              ),
              const SizedBox(width: 24),
              FilledButton.tonal(
                onPressed: () async {
                  await setCustomCss(_customCssController.text);
                  if (!mounted) return;
                  Navigator.pop(context);
                },
                child: const Text('保存'),
              ),
            ],
          )
        ],
      ),
    );
  }
}
