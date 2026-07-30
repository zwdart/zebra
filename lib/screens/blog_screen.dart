import 'package:flutter/material.dart';
import '../models/blog_post.dart';
import '../services/blog_service.dart';
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
  final List<BlogPost> _items = [];
  bool _isLoading = false;
  int _currentPage = 1;
  int _total = 0;
  final int _pageSize = 10;
  final TextEditingController _pageJumpController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadData(refresh: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _pageJumpController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  int get _totalPages => (_total / _pageSize).ceil().clamp(1, 9999);

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadData({bool refresh = false}) async {
    if (_isLoading) return;
    if (refresh) {
      _currentPage = 1;
      _items.clear();
    }

    setState(() => _isLoading = true);

    final result = await BlogService.getBlogPosts(
      page: _currentPage,
      size: _pageSize,
    );

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result != null) {
        if (refresh) _items.clear();
        _items.addAll(result.items);
        _total = result.total;
      }
    });
  }

  void _loadMore() {
    if (_isLoading || _items.length >= _total) return;
    _currentPage++;
    _loadData();
  }

  void _goToPage(int page) {
    final target = page.clamp(1, _totalPages);
    if (target != _currentPage) {
      setState(() {
        _currentPage = target;
      });
      _loadData(refresh: true);
    }
  }

  void _jumpToPage() {
    final page = int.tryParse(_pageJumpController.text);
    if (page != null) {
      _goToPage(page);
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

    if (widget.embedded) {
      return _buildBodyContent(context, loc, theme);
    }

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
      body: _buildBodyContent(context, loc, theme),
    );
  }

  Widget _buildBodyContent(BuildContext context, AppLocalizations loc, ThemeData theme) {
    return Column(
        children: [
          if (!widget.embedded && CustomTitleBar.isDesktop)
            CustomTitleBar(
              title: loc.blog,
              showBackButton: true,
            ),
          const SizedBox(height: 4),
          // Total count + pagination
          if (_total > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildPaginationControls(theme),
            ),
          const SizedBox(height: 4),
          // List
          Expanded(
            child: _items.isEmpty && _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(
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
                      )
                    : RefreshIndicator(
                        onRefresh: () => _loadData(refresh: true),
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: _items.length + (_isLoading ? 1 : 0),
                          itemBuilder: (ctx, i) {
                            if (i == _items.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            return _buildItemCard(_items[i], theme);
                          },
                        ),
                      ),
          ),
        ],
      );
  }

  Widget _buildPaginationControls(ThemeData theme) {
    final loc = AppLocalizations.of(context);
    return Row(
      children: [
        if (_totalPages > 1) ...[
          IconButton(
            icon: const Icon(Icons.first_page, size: 20),
            onPressed: _currentPage > 1 ? () => _goToPage(1) : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            onPressed: _currentPage > 1 ? () => _goToPage(_currentPage - 1) : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 48),
            alignment: Alignment.center,
            child: Text(
              '$_currentPage / $_totalPages',
              style: theme.textTheme.bodySmall,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: _currentPage < _totalPages
                ? () => _goToPage(_currentPage + 1)
                : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.last_page, size: 20),
            onPressed: _currentPage < _totalPages
                ? () => _goToPage(_totalPages)
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
