CC = g++
CPPFLAGS = "-I.. -D_DEBUG"
OBJ = TestFADBAD.o TestTAD.o TestAll.o

.cpp.o:
	$(CC) $(CFLAGS) $(CPPFLAGS) -c $<

TestAll : $(OBJ)
	$(CC) -o $@ $(OBJ)

all: TestAll

clean:
	-rm *.o TestAll
