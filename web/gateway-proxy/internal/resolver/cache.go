package resolver

import (
	"sync"
	"time"
)

type cacheEntry struct {
	backend   *Backend
	expiresAt time.Time
}

// Cache is a simple TTL cache using sync.RWMutex + map.
type Cache struct {
	mu      sync.RWMutex
	entries map[string]*cacheEntry
	done    chan struct{}
}

// NewCache creates a new TTL cache and starts a background goroutine
// that evicts expired entries every 30 seconds.
func NewCache() *Cache {
	c := &Cache{
		entries: make(map[string]*cacheEntry),
		done:    make(chan struct{}),
	}
	go c.evictLoop()
	return c
}

// Get returns the cached Backend for the given key, or nil and false if
// the key is not present or has expired.
func (c *Cache) Get(key string) (*Backend, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	entry, ok := c.entries[key]
	if !ok {
		return nil, false
	}
	if time.Now().After(entry.expiresAt) {
		return nil, false
	}
	return entry.backend, true
}

// Set stores a Backend in the cache with the given TTL.
func (c *Cache) Set(key string, backend *Backend, ttl time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.entries[key] = &cacheEntry{
		backend:   backend,
		expiresAt: time.Now().Add(ttl),
	}
}

// Delete removes a key from the cache.
func (c *Cache) Delete(key string) {
	c.mu.Lock()
	defer c.mu.Unlock()

	delete(c.entries, key)
}

// Stop stops the background eviction goroutine.
func (c *Cache) Stop() {
	close(c.done)
}

func (c *Cache) evictLoop() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			c.evictExpired()
		case <-c.done:
			return
		}
	}
}

func (c *Cache) evictExpired() {
	c.mu.Lock()
	defer c.mu.Unlock()

	now := time.Now()
	for key, entry := range c.entries {
		if now.After(entry.expiresAt) {
			delete(c.entries, key)
		}
	}
}
