import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/blog_post.dart';
import '../providers/blog_provider.dart';
import '../widgets/custom_title_bar.dart';
import '../l10n/app_localizations.dart';
import 'blog_detail_screen.dart';

class BlogScreen extends StatefulWidget {
  final bool embedded;

  const BlogScreen({super.key, this.embedded = false});

  @override
  State<BlogScreen> createState() => _BlogScreenState();
}

class _BlogScreenState extends State<BlogScreen> {
  final TextEditingController _pageJumpController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final provider = context.read<BlogProvider>();
    if (provider.items.isEmpty && !provider.isLoading) {
      provider.loadData(refresh: true);
    }
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _pageJumpController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<BlogProvider>().loadMore();
    }
  }

  void _jumpToPage() {
    final page = int.tryParse(_pageJumpController.text);
    if (page != null) {
      context.read<BlogProvider>().goToPage(page);
      _pageJumpController.clear();
    }
  }

  String _formatDate(String? s) {
    if (s == null || s.isEmpty) return '';
    final d = DateTime.tryParse(s);
    if (d == null) return s;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final provider = context.watch<BlogProvider>();
    final items = provider.items;
    final isLoading = provider.isLoading;
    final total = provider.total;
    final currentPage = provider.currentPage;
    final totalPages = provider.totalPages;

    final body = _buildBodyContent(loc, theme, items, isLoading, total, currentPage, totalPages);

    if (widget.embedded) return body;

    return Scaffold(
      appBar: CustomTitleBar.isDesktop
          ? null
          : AppBar(
              title: Text(loc.blog),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
            ),
      body: body,
    );
  }

  Widget _buildBodyContent(AppLocalizations loc, ThemeData theme,
      List<BlogPost> items, bool isLoading, int total, int currentPage, int totalPages) {
    return Column(
      children: [
        if (!widget.embedded && CustomTitleBar.isDesktop)
          CustomTitleBar(
            title: loc.blog,
            showBackButton: true,
          ),
        const SizedBox(height: 4),
        if (total > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildPaginationControls(theme, currentPage, totalPages),
          ),
        const SizedBox(height: 4),
        Expanded(
          child: items.isEmpty && isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () => context.read<BlogProvider>().loadData(refresh: true),
                  child: items.isEmpty
                      ? LayoutBuilder(
                          builder: (context, constraints) => SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: SizedBox(
                              height: constraints.maxHeight,
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.article_outlined,
                                        size: 64, color: theme.colorScheme.outline),
                                    const SizedBox(height: 16),
                                    Text(loc.blogEmpty,
                                        style: theme.textTheme.titleMedium),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: items.length + (isLoading ? 1 : 0),
                          itemBuilder: (ctx, i) {
                            if (i == items.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            return _buildItemCard(items[i], theme);
                          },
                        ),
                ),
        ),
      ],
    );
  }

  Widget _buildPaginationControls(ThemeData theme, int currentPage, int totalPages) {
    final loc = AppLocalizations.of(context);
    return Row(
      children: [
        if (totalPages > 1) ...[
          IconButton(
            icon: const Icon(Icons.first_page, size: 20),
            onPressed: currentPage > 1 ? () => context.read<BlogProvider>().goToPage(1) : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            onPressed: currentPage > 1 ? () => context.read<BlogProvider>().goToPage(currentPage - 1) : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 48),
            alignment: Alignment.center,
            child: Text(
              '$currentPage / $totalPages',
              style: theme.textTheme.bodySmall,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: currentPage < totalPages
                ? () => context.read<BlogProvider>().goToPage(currentPage + 1)
                : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.last_page, size: 20),
            onPressed: currentPage < totalPages
                ? () => context.read<BlogProvider>().goToPage(totalPages)
                : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          SizedBox(
            width: 56,
            height: 28,
            child: TextField(
              controller: _pageJumpController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: theme.colorScheme.primary),
                ),
                contentPadding: EdgeInsets.zero,
                isDense: true,
                hintText: loc.blogPage,
                hintStyle: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
              ),
              onSubmitted: (_) => _jumpToPage(),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.arrow_forward, size: 18),
            onPressed: _jumpToPage,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ],
    );
  }

  Widget _buildItemCard(BlogPost post, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openPostDetail(post),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (post.sortOrder > 0)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Icon(Icons.push_pin, size: 12, color: Colors.orange.shade600),
                    ),
                  Expanded(
                    child: Text(
                      post.title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (post.summary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  post.summary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (post.tagList.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: post.tagList.map((tag) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  )).toList(),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.access_time, size: 12, color: theme.colorScheme.outline),
                  const SizedBox(width: 2),
                  Text(
                    _formatDate(post.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPostDetail(BlogPost post) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BlogDetailScreen(post: post)),
    );
  }
}
