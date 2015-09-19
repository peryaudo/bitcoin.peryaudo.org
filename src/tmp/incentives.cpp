#include <iostream>

long long f(long long height) {return (50LL * 100000000LL) >> (height / 210000LL);}

int main() {
	using namespace std;
	for (long long i = 0LL; i < (1LL << 24LL); i += (1LL << 14LL)) {
		cout<<i<<", "<<f(i)<<endl;
	}
}

