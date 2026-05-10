CXX      := clang++
CXXFLAGS := -std=c++20 -O2 -Wall -Wextra -Wno-unused-parameter $(shell pkg-config --cflags sdl3)
LDFLAGS  := $(shell pkg-config --libs sdl3)

SRCS := $(wildcard src/*.cpp)
OBJS := $(SRCS:.cpp=.o)
DEPS := $(OBJS:.o=.d)

BIN := bsprenderer

$(BIN): $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LDFLAGS)

src/%.o: src/%.cpp
	$(CXX) $(CXXFLAGS) -MMD -MP -c -o $@ $<

-include $(DEPS)

run: $(BIN)
	./$(BIN)

clean:
	rm -f $(OBJS) $(DEPS) $(BIN)

.PHONY: run clean
