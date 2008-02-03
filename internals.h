- (NSMethodSignature *) methodSignatureForSelector:(SEL)selector {
    fprintf(stderr, "[%s]S-%s\n", self->isa->name, sel_getName(selector));
    return [super methodSignatureForSelector:selector];
}

- (BOOL) respondsToSelector:(SEL)selector {
    fprintf(stderr, "[%s]R-%s\n", self->isa->name, sel_getName(selector));
    return [super respondsToSelector:selector];
}
