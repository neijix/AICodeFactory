export function Card({ user, onOpen }: Props) {
  return (
    <div className="card" onClick={() => onOpen(user.id)}>
      <img src={user.avatar} className="h-screen" />
      <button onClick={() => onOpen(user.id)} className="transition-all text-[10px]"><CloseIcon /></button>
      <input value={user.name} onPaste={(e) => e.preventDefault()} />
    </div>
  );
}
