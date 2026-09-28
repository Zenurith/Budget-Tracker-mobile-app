import 'package:flutter/widgets.dart';

import '../presentation/presenter.dart';

class PresenterBuilder<S> extends StatelessWidget {
  final Presenter<S> presenter;
  final Widget Function(BuildContext context, S state) builder;
  const PresenterBuilder({
    super.key,
    required this.presenter,
    required this.builder,
  });
  @override
  Widget build(BuildContext context) => StreamBuilder<S>(
    stream: presenter.states,
    initialData: presenter.state,
    builder: (context, _) => builder(context, presenter.state),
  );
}
